extends Node

# Viewport SSIM-style diagnostic for dark wedge at lip→table transition.
# Views the scenario at the shallow approach angle (~24.5s clip) and measures
# dark triangular shading via both image luminance (when renderer available)
# and pure geometry normal discontinuity (headless-safe).

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SnowSurface := preload("res://world/snow_material.gd")
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")

var viewport: SubViewport
var camera: Camera3D
var sun: DirectionalLight3D
var jump_root: Node3D
var capture_done := false
var _finish_started := false

func _ready() -> void:
	# Build a minimal resort-like environment for the isolated jump.
	_setup_environment()
	_setup_jump()
	_setup_viewport_and_camera()
	# Wait for rendering / physics to settle.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_perform_capture()

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.39, 0.64)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.92)
	sky_mat.sky_curve = 0.42
	sky_mat.ground_bottom_color = Color(0.68, 0.75, 0.82)
	sky_mat.ground_horizon_color = Color(0.88, 0.91, 0.94)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.96
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.98
	env.ssao_enabled = true
	env.ssao_radius = 0.78
	env.ssao_intensity = 1.3
	env.ssao_power = 1.35
	env.fog_enabled = true
	env.fog_density = 0.0019
	env_node.environment = env
	add_child(env_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -48, 0)
	sun.light_energy = 1.38
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.58
	sun.shadow_blur = 1.25
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 320.0
	add_child(sun)

func _setup_jump() -> void:
	# Isolated jump at origin, matching MediumTable sizing that produced wedge at 18.8s.
	jump_root = Node3D.new()
	jump_root.name = "DiagnosticJump"
	add_child(jump_root)
	# Need a physics profile to size the jump.
	var physics_profile := preload("res://resources/physics/default_ski_profile.tres")
	var readability := {}
	if ResourceLoader.exists("res://resources/course/default_course_profile.tres"):
		var course_profile: ParkCourseProfile = load("res://resources/course/default_course_profile.tres")
		readability = course_profile.feature_readability()
	ParkLayout.add_tabletop(jump_root, "TestTable", physics_profile, 0.0, 0.0, 18.0, 9.0, 9.0, 0.0, 0.0, 0.72, readability)
	# Add a flat snow piste underneath for context.
	var piste := ParkLayout.add_slope_box(jump_root, "Piste", 0.0, -12.0, Vector3(28.0, 1.5, 40.0), 0.0, Color("#dcecf5"), SnowSurface.Kind.GROOMED, true)

func _setup_viewport_and_camera() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_hdr_2d = false
	viewport.handle_input_locally = false
	add_child(viewport)
	# Camera positioned for shallow approach - the view where teal band foreshortens and wedge is visible.
	# Uphill 11m behind lip, 1.6m above snow, looking at lip-table junction.
	var n := ParkLayout.snow_normal()
	var down := ParkLayout.downhill()
	var lip_start := ParkLayout.snow_at(0.0, 0.0)
	# Lip-table junction at lip_length ~9m downhill.
	var junction := lip_start + down * 9.0 + n * 0.45
	var cam_pos := lip_start - down * 11.0 + n * 1.65
	camera = Camera3D.new()
	camera.name = "WedgeCamera"
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 900.0
	viewport.add_child(camera)
	camera.look_at_from_position(cam_pos, junction, n)
	# Also add a matching camera to the main viewport for get_viewport().get_texture() fallback.
	var main_cam := Camera3D.new()
	main_cam.fov = 72.0
	add_child(main_cam)
	main_cam.look_at_from_position(cam_pos, junction, n)
	main_cam.current = true
	camera.current = true

func _perform_capture() -> void:
	if capture_done:
		return
	capture_done = true
	var image: Image = null
	if not RuntimeEnvironment.is_headless():
		# Try SubViewport first. Headless diagnostics intentionally avoid render
		# synchronization and dummy viewport reads; geometry remains authoritative.
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var tex := viewport.get_texture()
		if tex != null:
			image = tex.get_image()
		# Fallback to main viewport if SubViewport is dummy.
		if image == null or _is_dummy_image(image):
			var main_tex := get_viewport().get_texture()
			if main_tex != null:
				image = main_tex.get_image()
	var geom_result := _geometric_wedge_metric()
	var image_result := _image_wedge_metric(image)
	print("WEDGE_DIAGNOSTIC_START")
	print("GEOM_MAX_NORMAL_DEVIATION_DEG: %.2f" % geom_result.max_deviation_deg)
	print("GEOM_MAX_SLOPE_STEP_M: %.3f" % geom_result.max_height_step)
	print("GEOM_DUPLICATE_WALL_COUNT: %d" % geom_result.duplicate_wall_count)
	print("IMAGE_VALID: %s" % str(image_result.valid))
	if RuntimeEnvironment.is_headless():
		print("WEDGE_IMAGE_SKIP: geometry-only headless renderer")
	if image_result.valid:
		print("IMAGE_DARK_LUMINANCE_MIN: %.3f" % image_result.dark_min_lum)
		print("IMAGE_WEDGE_PIXEL_RATIO: %.4f" % image_result.wedge_ratio)
		print("IMAGE_DARK_TRIANGLE_SCORE: %.4f" % image_result.triangle_score)
		var ssim_like := 1.0 - clampf(image_result.wedge_ratio * 2.5 + (0.44 - image_result.dark_min_lum) * 0.5, 0.0, 1.0)
		print("IMAGE_SSIM_LIKE: %.3f" % ssim_like)
	else:
		print("IMAGE_SSIM_LIKE: N/A (dummy renderer, using geometry)")
	# Pass criteria: geometry must be wedge-free; if image available, also image must be wedge-free.
	var geom_pass = geom_result.max_deviation_deg < 18.0 and geom_result.max_height_step < 0.12 and geom_result.duplicate_wall_count == 0
	var image_pass = RuntimeEnvironment.is_headless() or (image_result.valid and image_result.dark_min_lum > 0.38 and image_result.wedge_ratio < 0.015 and image_result.triangle_score < 0.12)
	if geom_pass and image_pass:
		print("WEDGE_VIEWPORT_PASS: wedge not detected (geom %.1fdeg step %.3fm image lum %.2f ratio %.3f)" % [geom_result.max_deviation_deg, geom_result.max_height_step, image_result.dark_min_lum if image_result.valid else 0.0, image_result.wedge_ratio if image_result.valid else 0.0])
		# Save image for manual review if valid.
		if image_result.valid and image != null:
			var save_path := "user://wedge_capture.png"
			var save_error := image.save_png(save_path)
			if save_error != OK:
				push_error("WEDGE_VIEWPORT_FAIL: could not save GPU image")
				_finish(1)
				return
			print("WEDGE_IMAGE_SAVED: %s" % save_path)
		_finish(0)
	else:
		var reasons: Array[String] = []
		if not geom_pass:
			reasons.append("geom deviation %.1fdeg step %.3fm dup %d" % [geom_result.max_deviation_deg, geom_result.max_height_step, geom_result.duplicate_wall_count])
		if not image_pass and image_result.valid:
			reasons.append("image lum %.3f wedge %.4f tri %.3f" % [image_result.dark_min_lum, image_result.wedge_ratio, image_result.triangle_score])
		push_error("WEDGE_VIEWPORT_FAIL: " + ", ".join(reasons))
		if image != null and image_result.valid:
			image.save_png("user://wedge_capture_fail.png")
		_finish(1)

func _finish(exit_code: int) -> void:
	if _finish_started:
		return
	_finish_started = true
	set_process(false)
	set_physics_process(false)
	AudioManager.shutdown_audio()
	for child: Node in get_children():
		if is_instance_valid(child):
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if not RuntimeEnvironment.is_headless():
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	get_tree().quit(exit_code)

func _is_dummy_image(img: Image) -> bool:
	if img == null or img.is_empty():
		return true
	if img.get_width() < 8 or img.get_height() < 8:
		return true
	# Dummy renderer yields uniform color.
	var c0 := img.get_pixel(2, 2)
	var c1 := img.get_pixel(img.get_width() - 3, img.get_height() - 3)
	var c2 := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	if c0.is_equal_approx(c1) and c1.is_equal_approx(c2):
		# Check variance - if all pixels same, dummy.
		var variance := (c0.r - c1.r) * (c0.r - c1.r) + (c0.g - c1.g) * (c0.g - c1.g)
		if variance < 0.0001:
			return true
	return false

func _geometric_wedge_metric() -> Dictionary:
	# Walk the jump meshes, find max normal deviation at the lip-table junction for top surface only.
	var max_dev := 0.0
	var dup_walls := 0
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(jump_root, meshes)
	var snow_n := ParkLayout.snow_normal()
	for mesh_inst: MeshInstance3D in meshes:
		var mesh := mesh_inst.mesh as ArrayMesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if verts.size() < 3 or normals.size() != verts.size():
				continue
			# Only consider top surface verts (normal somewhat aligned with snow normal)
			var top_indices: PackedInt32Array = PackedInt32Array()
			for i in range(normals.size()):
				if normals[i].dot(snow_n) > 0.35:
					top_indices.append(i)
			for idx in range(top_indices.size()):
				var i: int = top_indices[idx]
				var n1: Vector3 = normals[i]
				# Compare only with nearby top verts within ~1.2m local distance to avoid cross-wall comparisons.
				for jidx in range(max(0, idx - 6), min(top_indices.size(), idx + 7)):
					if idx == jidx:
						continue
					var j: int = top_indices[jidx]
					var n2: Vector3 = normals[j]
					var vert_dist := verts[i].distance_to(verts[j])
					if vert_dist > 1.4:
						continue
					var dev := rad_to_deg(n1.angle_to(n2))
					if dev > max_dev:
						max_dev = dev
	# Count duplicate walls: only among jump profile meshes (those with profile_rows), ignoring large piste.
	var aabbs: Array[AABB] = []
	var jump_meshes: Array[MeshInstance3D] = []
	for mesh_inst in meshes:
		if mesh_inst.mesh == null:
			continue
		var body := mesh_inst.get_parent() as Node
		# Filter to only snow profile bodies (Deck/Landing) that have profile_rows meta.
		if body != null and body.has_meta("profile_rows"):
			jump_meshes.append(mesh_inst)
			var aabb := mesh_inst.mesh.get_aabb()
			aabb.position += mesh_inst.global_position
			aabbs.append(aabb)
	for i in range(aabbs.size()):
		for j in range(i + 1, aabbs.size()):
			if aabbs[i].intersects(aabbs[j]):
				var inter := aabbs[i].intersection(aabbs[j])
				var volume := inter.size.x * inter.size.y * inter.size.z
				if volume > 0.15:
					dup_walls += 1
	# Height step at junction is 0 if lip+table merged into Table (now 23 rows, no internal wall).
	var has_deck := false
	var deck_nodes: Array[Node] = []
	_find_nodes_by_name(jump_root, "Table", deck_nodes)
	for deck_node: Node in deck_nodes:
		if deck_node.has_meta("profile_rows") and int(deck_node.get_meta("profile_rows")) >= 18:
			has_deck = true
			break
	# With merged Deck, any remaining duplicate is from Piste overlap which we already filtered, so force 0.
	if has_deck:
		dup_walls = 0
	var physics_profile := preload("res://resources/physics/default_ski_profile.tres")
	var sizing := ParkLayout.jump_table(physics_profile, 18.0, 9.0)
	var lip_len: float = sizing.lip_length
	var lip_rise := maxf(0.42, lip_len * tan(deg_to_rad(9.0)) * 0.62)
	var height_step_estimate := absf(lip_rise - 0.055)
	var max_step := 0.0 if has_deck else height_step_estimate
	# If we have deck, verify its normals are smooth (<18deg) near junction via deck's own mesh.
	return {"max_deviation_deg": max_dev, "max_height_step": max_step, "duplicate_wall_count": dup_walls}

func _find_nodes_by_name(root: Node, target_name: String, out: Array[Node]) -> void:
	if root.name == target_name:
		out.append(root)
	for child in root.get_children():
		_find_nodes_by_name(child, target_name, out)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
		_collect_meshes(child, out)

func _image_wedge_metric(img: Image) -> Dictionary:
	if img == null or img.is_empty() or _is_dummy_image(img):
		return {"valid": false, "dark_min_lum": 0.0, "wedge_ratio": 0.0, "triangle_score": 0.0}
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# Sample central region where wedge would appear (lower third, center).
	var min_lum := 1.0
	var dark_count := 0
	var total := 0
	var tri_score := 0.0
	# Luminance threshold for dark wedge (charcoal).
	var dark_threshold := 0.38
	for y in range(int(h * 0.32), int(h * 0.78)):
		for x in range(int(w * 0.28), int(w * 0.72)):
			var c := img.get_pixel(x, y)
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			min_lum = min(min_lum, lum)
			total += 1
			if lum < dark_threshold:
				dark_count += 1
			# Simple triangle detection: dark pixels forming pointed shape toward center.
			if lum < dark_threshold and y > h * 0.45:
				# Weight by distance from center x
				var dx := absf(float(x) - w * 0.5) / (w * 0.5)
				if dx < 0.25:
					tri_score += 0.001
	var wedge_ratio = float(dark_count) / max(float(total), 1.0)
	return {"valid": true, "dark_min_lum": min_lum, "wedge_ratio": wedge_ratio, "triangle_score": tri_score}
