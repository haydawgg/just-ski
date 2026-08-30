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

static func add_tabletop(parent: Node3D, label: String, physics_profile: SkiPhysicsProfile, x: float, lip_z: float, design_speed: float, extra_lip_deg: float, width: float = 8.5, drop: float = 0.0, yaw_deg: float = 0.0, design_pop_strength: float = -1.0, readability: Dictionary = {}) -> Node3D:
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
	# The table is a rounded knuckle mound. Fix wedge by merging lip+table into a single C1-continuous deck with no internal wall.
	var table_centers: Array[Vector3] = []
	var table_widths := PackedFloat32Array()
	var table_shoulders := PackedFloat32Array()
	var table_samples := 10
	for sample: int in range(table_samples):
		var t := float(sample) / float(table_samples - 1)
		var distance_along := lip_length + table_length * t
		var knuckle_height := _hermite(t, lip_rise, 0.055, tan(extra), 0.0, table_length)
		table_centers.append(lip_start + down * distance_along + n * knuckle_height)
		table_widths.append(width * lerpf(1.0, 1.34, _smootherstep(t)))
		table_shoulders.append(maxf(knuckle_height - 0.001, 0.0))
	var deck_centers: Array[Vector3] = []
	var deck_widths := PackedFloat32Array()
	var deck_shoulders := PackedFloat32Array()
	deck_centers.append_array(lip_centers)
	deck_widths.append_array(lip_widths)
	deck_shoulders.append_array(lip_shoulders)
	for i: int in range(1, table_centers.size()):
		deck_centers.append(table_centers[i])
		deck_widths.append(table_widths[i])
		deck_shoulders.append(table_shoulders[i])
	_add_profiled_snow_body(root, "Table", deck_centers, deck_widths, deck_shoulders, n, 0.60, SnowSurface.Kind.GROOMED, 0.28, true)

	# A raised knuckle rolls progressively back into the piste, giving both the
	# touchdown and run-out a matched tangent instead of a landing slab edge.
	var landing_centers: Array[Vector3] = []
	var landing_widths := PackedFloat32Array()
	var landing_shoulders := PackedFloat32Array()
	var run_out_length := clampf(landing_length * 0.28, 3.5, 6.0)
	var landing_samples := 14
	var landing_crown := clampf(0.28 + lip_rise * 0.22, 0.42, 0.82)
	var flat_gap := 1.8
	for sample: int in range(landing_samples):
		var t := float(sample) / float(landing_samples - 1)
		var distance_along := lip_length + table_length + flat_gap + (landing_length + run_out_length) * t
		var landing_t := clampf((landing_length + run_out_length) * t / landing_length, 0.0, 1.0)
		var height := 0.001 + landing_crown * (1.0 - _smootherstep(landing_t))
		landing_centers.append(lip_start + down * distance_along + n * height)
		landing_widths.append(width * lerpf(1.28, 1.62, _smootherstep(t)))
		landing_shoulders.append(maxf(height - 0.001, 0.0))
	_add_profiled_snow_body(root, "Landing", landing_centers, landing_widths, landing_shoulders, n, 0.68, SnowSurface.Kind.PACKED, 0.28, true, SnowSurface.Kind.GROOMED)
	_add_jump_readability_markers(root, lip_centers, lip_widths, lip_shoulders, landing_centers, landing_widths, landing_shoulders, n, readability)
	root.set_meta("lip_z", lip_z)
	root.set_meta("table_length", table_length)
	root.set_meta("range", sizing.range)
	root.set_meta("profile_samples", deck_centers.size() + landing_samples)
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

static func add_hip(parent: Node3D, label: String, physics_profile: SkiPhysicsProfile, x: float, lip_z: float, design_speed: float, extra_lip_deg: float, yaw_deg: float, design_pop_strength: float = -1.0, readability: Dictionary = {}) -> Node3D:
	return add_tabletop(parent, label, physics_profile, x, lip_z, design_speed, extra_lip_deg, 9.0, 0.0, yaw_deg, design_pop_strength, readability)

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
	var feature_basis := downhill_basis(yaw_deg)
	var snow_base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.72, 0.12, length + 0.45)
	snow_base.mesh = base_mesh
	snow_base.position = snow_at(x, z) + snow_normal() * 0.055
	snow_base.basis = feature_basis
	snow_base.material_override = SnowSurface.create(SnowSurface.Kind.PACKED, Vector2(feature_basis.z.x, feature_basis.z.z), 0.28)
	snow_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(snow_base)
	_add_feature_snow_collar(root, feature_basis, snow_at(x, z) + snow_normal() * 0.026, Vector3(1.14, 0.1, length + 0.7))
	var body := StaticBody3D.new()
	body.name = "RideSurface"
	body.collision_layer = 1
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", SnowSurface.Kind.GROOMED)
	body.set_meta("ski_surface_class", "feature")
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
	var snow_cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.5, 0.08, length + 0.12)
	snow_cap.mesh = cap_mesh
	snow_cap.position = snow_at(x, z) + feature_basis.y * (height + 0.045)
	snow_cap.basis = feature_basis
	snow_cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER, Vector2(feature_basis.z.x, feature_basis.z.z), 0.34)
	snow_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(snow_cap)
	_add_feature_trim(root, feature_basis, snow_at(x, z) + feature_basis.y * (height + 0.012), Vector3(0.56, 0.06, length + 0.18), color.darkened(0.18))
	for support_offset: float in [-length * 0.36, 0.0, length * 0.36]:
		_add_feature_trim(root, feature_basis, snow_at(x, z) + feature_basis.y * (height * 0.18) + feature_basis.z * support_offset, Vector3(0.13, height * 0.34, 0.13), color.darkened(0.25))
	return root

static func add_bonk(parent: Node3D, label: String, x: float, z: float, height: float, radius: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_bonks")
	parent.add_child(root)
	var snow_base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = radius * 1.35
	base_mesh.bottom_radius = radius * 1.65
	base_mesh.height = 0.12
	base_mesh.radial_segments = 10
	snow_base.mesh = base_mesh
	snow_base.position = snow_at(x, z) + snow_normal() * 0.06
	snow_base.material_override = SnowSurface.create(SnowSurface.Kind.PACKED, Vector2(0.0, -1.0), 0.22)
	snow_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(snow_base)
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
	var snow_cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = radius * 0.72
	cap_mesh.bottom_radius = radius * 1.08
	cap_mesh.height = 0.1
	cap_mesh.radial_segments = 10
	snow_cap.mesh = cap_mesh
	snow_cap.position = snow_at(x, z) + snow_normal() * (height + 0.045)
	snow_cap.material_override = SnowSurface.create(SnowSurface.Kind.POWDER, Vector2(0.0, -1.0), 0.22)
	snow_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(snow_cap)
	_add_feature_snow_collar(root, downhill_basis(), snow_at(x, z) + snow_normal() * 0.026, Vector3(radius * 3.2, 0.1, radius * 3.2))
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shape_node.shape = shape
	body.add_child(shape_node)
	root.add_child(body)
	return root

static func _add_feature_snow_collar(parent: Node3D, basis: Basis, center: Vector3, size: Vector3) -> void:
	var collar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	collar.mesh = mesh
	collar.position = center
	collar.basis = basis
	collar.material_override = SnowSurface.create(SnowSurface.Kind.PACKED, Vector2(basis.z.x, basis.z.z), 0.2)
	collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(collar)

static func _add_feature_trim(parent: Node3D, basis: Basis, center: Vector3, size: Vector3, color: Color) -> void:
	var trim := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	trim.mesh = mesh
	trim.position = center
	trim.basis = basis
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.2
	material.roughness = 0.42
	trim.material_override = material
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(trim)

static func add_cannon(parent: Node3D, label: String, x: float, z: float, length: float, width: float, height: float) -> Node3D:
	var root := add_side_hit(parent, label, x, z, length, height, width, 0.0)
	root.add_to_group("park_cannons")
	return root

static func add_gate(parent: Node3D, label: String, x: float, z: float, width: float, color: Color, tuning: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.add_to_group("park_gates")
	parent.add_child(root)
	var normal := snow_normal()
	var center := snow_at(x, z)
	var destination_gate := width >= 30.0
	var visual_width := minf(width, 18.0 if destination_gate else 13.0)
	var post_height := 2.45 if destination_gate else 2.0
	var post_thickness := 0.14
	var flag_size := Vector2(0.98 if destination_gate else 0.84, 0.56 if destination_gate else 0.48)
	var guide_color := color.lerp(Color("#d8eef2"), 0.28)
	for side: float in [-1.0, 1.0]:
		var anchor := center + Vector3.RIGHT * visual_width * 0.5 * side
		_add_gate_post(root, anchor + normal * (post_height * 0.5), Vector3(post_thickness, post_height, post_thickness), Color("#35515d"))
		_add_gate_flag(root, anchor + normal * (post_height - flag_size.y * 0.55), flag_size, guide_color, side)
	root.set_meta("guidance_style", "minimal_flag_posts")
	root.set_meta("non_colliding", true)
	return root

static func _add_gate_post(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	instance.material_override = material
	_configure_guide_visibility(instance)
	parent.add_child(instance)

static func _add_gate_flag(parent: Node3D, position: Vector3, size: Vector2, color: Color, side: float) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "RouteFlag"
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Z
	instance.mesh = mesh
	instance.position = position + Vector3.RIGHT * side * size.x * 0.46
	instance.rotation_degrees.y = -8.0 * side
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.86
	instance.material_override = material
	_configure_guide_visibility(instance)
	instance.add_to_group("route_guide_flags")
	parent.add_child(instance)

static func _configure_guide_visibility(instance: GeometryInstance3D) -> void:
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_begin = 2.5
	instance.visibility_range_begin_margin = 3.0
	instance.visibility_range_end = 88.0
	instance.visibility_range_end_margin = 24.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

static func add_slope_box(parent: Node3D, label: String, x: float, z: float, size: Vector3, yaw_deg: float, color: Color, surface_kind: int, collision_enabled: bool, extra_height: float = 0.0, visual_surface_kind: int = -1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	var n := snow_normal()
	body.transform = Transform3D(downhill_basis(yaw_deg), snow_at(x, z) + n * (extra_height - size.y * 0.5))
	body.collision_layer = 1 if collision_enabled else 0
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", surface_kind)
	body.set_meta("ski_surface_class", "snow")
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
	for support_index: int in range(points.size()):
		_add_rail_support(root, points[support_index], normal, support_index)
	_add_rail_apron(root, "Approach", points[0], entry_tangent, normal, true)
	_add_rail_apron(root, "Runout", points[-1], exit_tangent, normal, false)
	return root

static func _add_rail_support(parent: Node3D, anchor: Vector3, normal: Vector3, support_index: int) -> void:
	var snow_position := snow_at(anchor.x, anchor.z)
	var above_snow := anchor.y - snow_position.y
	if above_snow < 0.34:
		return
	var support_height := clampf(above_snow - 0.14, 0.24, 4.5)
	var support := MeshInstance3D.new()
	support.name = "RailSupport_%02d" % support_index
	var support_mesh := BoxMesh.new()
	support_mesh.size = Vector3(0.14, support_height, 0.14)
	support.mesh = support_mesh
	support.position = Vector3(anchor.x, snow_position.y + support_height * 0.5 + 0.035, anchor.z)
	var support_material := StandardMaterial3D.new()
	support_material.albedo_color = Color("#55676c")
	support_material.metallic = 0.22
	support_material.roughness = 0.62
	support.material_override = support_material
	support.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(support)
	_add_feature_snow_collar(parent, Basis.IDENTITY, snow_position + normal * 0.028, Vector3(0.42, 0.07, 0.42))

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
	material.albedo_color = color.lerp(Color("#75858a"), 0.16)
	material.roughness = 0.68
	material.metallic = 0.03
	return material

static func _add_jump_readability_markers(
	parent: Node3D,
	lip_centers: Array[Vector3],
	lip_widths: PackedFloat32Array,
	lip_edge_drops: PackedFloat32Array,
	landing_centers: Array[Vector3],
	landing_widths: PackedFloat32Array,
	landing_edge_drops: PackedFloat32Array,
	normal: Vector3,
	tuning: Dictionary
) -> void:
	if lip_centers.size() < 2 or landing_centers.size() < 2:
		return
	var takeoff_depth := clampf(float(tuning.get("takeoff_depth", 0.36)), 0.08, 0.5)
	var landing_length := clampf(float(tuning.get("landing_length", 4.5)), 1.0, 6.0)
	var landing_width := clampf(float(tuning.get("landing_width", 0.18)), 0.04, 0.3)
	var surface_offset := clampf(float(tuning.get("surface_offset", 0.025)), 0.005, 0.08)
	var marker_color: Color = tuning.get("color", Color("#2aa6bd"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var lip_last := lip_centers.size() - 1
	var lip_row_distance := lip_centers[lip_last].distance_to(lip_centers[lip_last - 1])
	var lip_blend := clampf(takeoff_depth / maxf(lip_row_distance, 0.001), 0.0, 1.0)
	var band_start_center := lip_centers[lip_last].lerp(lip_centers[lip_last - 1], lip_blend)
	var band_start_width := lerpf(lip_widths[lip_last], lip_widths[lip_last - 1], lip_blend)
	var band_start_drop := lerpf(lip_edge_drops[lip_last], lip_edge_drops[lip_last - 1], lip_blend)
	_add_profile_marker_quad(
		st,
		band_start_center, band_start_width, band_start_drop,
		lip_centers[lip_last], lip_widths[lip_last], lip_edge_drops[lip_last],
		-0.82, 0.82, normal, surface_offset
	)

	var marked_length := 0.0
	for row_index: int in range(1, landing_centers.size()):
		if marked_length >= landing_length:
			break
		var row_distance := landing_centers[row_index - 1].distance_to(landing_centers[row_index])
		if row_distance <= 0.001:
			continue
		var remaining := landing_length - marked_length
		var row_blend := minf(remaining / row_distance, 1.0)
		var end_center := landing_centers[row_index - 1].lerp(landing_centers[row_index], row_blend)
		var end_width := lerpf(landing_widths[row_index - 1], landing_widths[row_index], row_blend)
		var end_drop := lerpf(landing_edge_drops[row_index - 1], landing_edge_drops[row_index], row_blend)
		for side: float in [-0.72, 0.72]:
			_add_profile_marker_strip(
				st,
				landing_centers[row_index - 1], landing_widths[row_index - 1], landing_edge_drops[row_index - 1],
				end_center, end_width, end_drop,
				side, landing_width, normal, surface_offset
			)
		marked_length += row_distance * row_blend

	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var marker := MeshInstance3D.new()
	marker.name = "ReadabilityMarkers"
	marker.mesh = mesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visibility_range_end = 145.0
	marker.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(marker_color.lerp(Color("#d9e9e7"), 0.24), 0.68)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.roughness = 0.86
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.add_to_group("park_readability_markers")
	parent.add_child(marker)

static func _add_profile_marker_strip(
	st: SurfaceTool,
	start_center: Vector3,
	start_width: float,
	start_drop: float,
	end_center: Vector3,
	end_width: float,
	end_drop: float,
	across_center: float,
	world_width: float,
	normal: Vector3,
	surface_offset: float
) -> void:
	var start_half_across := world_width / maxf(start_width, 0.001)
	var end_half_across := world_width / maxf(end_width, 0.001)
	_add_profile_marker_quad(
		st,
		start_center, start_width, start_drop,
		end_center, end_width, end_drop,
		across_center - start_half_across, across_center + start_half_across,
		normal, surface_offset,
		across_center - end_half_across, across_center + end_half_across
	)

static func _add_profile_marker_quad(
	st: SurfaceTool,
	start_center: Vector3,
	start_width: float,
	start_drop: float,
	end_center: Vector3,
	end_width: float,
	end_drop: float,
	start_across_left: float,
	start_across_right: float,
	normal: Vector3,
	surface_offset: float,
	end_across_left: float = INF,
	end_across_right: float = INF
) -> void:
	if not is_finite(end_across_left):
		end_across_left = start_across_left
	if not is_finite(end_across_right):
		end_across_right = start_across_right
	var longitudinal := end_center - start_center
	var right := longitudinal.cross(normal).normalized()
	if right.length_squared() < 0.001:
		return
	var a := _profile_marker_point(start_center, start_width, start_drop, right, normal, start_across_left, surface_offset)
	var b := _profile_marker_point(end_center, end_width, end_drop, right, normal, end_across_left, surface_offset)
	var c := _profile_marker_point(end_center, end_width, end_drop, right, normal, end_across_right, surface_offset)
	var d := _profile_marker_point(start_center, start_width, start_drop, right, normal, start_across_right, surface_offset)
	_add_smooth_tri(st, a, d, c, normal, normal, normal, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE)
	_add_smooth_tri(st, a, c, b, normal, normal, normal, Vector2.ZERO, Vector2.ONE, Vector2.DOWN)
	var wall_height := 0.032
	var a_low := a - normal * wall_height
	var b_low := b - normal * wall_height
	var c_low := c - normal * wall_height
	var d_low := d - normal * wall_height
	_add_flat_quad(st, a, b, b_low, a_low)
	_add_flat_quad(st, b, c, c_low, b_low)
	_add_flat_quad(st, c, d, d_low, c_low)
	_add_flat_quad(st, d, a, a_low, d_low)

static func _profile_marker_point(center: Vector3, width: float, edge_drop: float, right: Vector3, normal: Vector3, across: float, surface_offset: float) -> Vector3:
	var clamped_across := clampf(across, -0.96, 0.96)
	var shoulder := smoothstep(0.58, 1.0, absf(clamped_across))
	return center + right * (width * 0.5 * clamped_across) - normal * edge_drop * shoulder + normal * surface_offset

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
	body.set_meta("ski_surface_class", "snow")
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
	body.set_meta("ski_surface_class", "snow")
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
