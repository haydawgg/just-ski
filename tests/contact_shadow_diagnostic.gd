extends Node

# Diagnostic for air-height contact shadow: verifies that the shadow is directly beneath,
# restrained, distance-sensitive, and provides height cue without being a blob.

const ParkLayout := preload("res://world/park_features/park_layout.gd")

var skier: SkierController
var viewport: SubViewport
var results: Array[Dictionary] = []

func _ready() -> void:
	# Build a minimal resort to get a skier with contact shadow
	var resort := load("res://world/resort.tscn").instantiate() as Node3D
	add_child(resort)
	await get_tree().process_frame
	await get_tree().process_frame
	skier = resort.get_node_or_null("Skier") as SkierController
	if skier == null:
		skier = resort.find_children("*", "SkierController", true, false).front() as SkierController
	if skier == null:
		push_error("CONTACT_SHADOW_FAIL: skier not found")
		get_tree().quit(1)
		return
	# SubViewport for image capture (shares main world)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_3d = get_viewport().world_3d
	add_child(viewport)
	var cam := Camera3D.new()
	cam.fov = 68.0
	viewport.add_child(cam)
	# Position camera to look downhill at shallow angle (height cue scenario)
	var n := ParkLayout.snow_normal()
	var down := ParkLayout.downhill()
	var focus := ParkLayout.snow_at(0.0, 30.0) + n * 0.5
	var cam_pos := focus - down * 14.0 + n * 4.2 + Vector3(4.0, 0, 0)
	cam.look_at_from_position(cam_pos, focus, n)
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	_run_height_sweep()

func _run_height_sweep() -> void:
	if skier == null:
		get_tree().quit(1)
		return
	var n := ParkLayout.snow_normal()
	var base_pos := ParkLayout.snow_at(0.0, 30.0) + n * 0.9
	# Test heights: ground (0.2), low air (1.5), mid (4.0), high (8.0)
	var heights := [0.25, 1.6, 4.2, 8.5]
	for h in heights:
		skier.global_position = base_pos + n * h
		skier.velocity = Vector3.ZERO
		skier.state = SkierController.State.AIR if h > 0.5 else SkierController.State.GROUND
		skier.contact.grounded = h < 0.5
		skier.contact.average_hit_position = base_pos
		skier.contact.average_normal = n
		skier.contact.confidence = 1.0 if h < 0.5 else 0.6
		# Force shadow update
		skier._update_contact_shadow(0.016)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shadow := skier.get_node_or_null("ContactShadow") as MeshInstance3D
		var visible := shadow != null and shadow.visible
		var alpha := 0.0
		if shadow != null and shadow.material_override is ShaderMaterial:
			var mat := shadow.material_override as ShaderMaterial
			alpha = float(mat.get_shader_parameter("shadow_opacity"))
		var shadow_pos := shadow.global_position if shadow != null else Vector3.ZERO
		var dist_to_ground := (skier.global_position - shadow_pos).length() if shadow != null else 0.0
		# Separation on screen: project both points via main viewport camera (resort's CameraRig)
		var cam_rig := skier.get_parent().get_node_or_null("CameraRig") as Node3D
		var cam3d: Camera3D = null
		if cam_rig != null:
			cam3d = cam_rig.get_node_or_null("Camera3D") as Camera3D
			if cam3d == null:
				cam3d = cam_rig.find_children("*", "Camera3D", true, false).front() as Camera3D
		var screen_separation := 0.0
		if cam3d != null and cam3d.is_inside_tree():
			var p_skier = cam3d.unproject_position(skier.global_position)
			var p_shadow = cam3d.unproject_position(shadow_pos)
			screen_separation = p_skier.distance_to(p_shadow)
		results.append({"height": h, "visible": visible, "alpha": alpha, "screen_sep": screen_separation, "shadow_y": shadow_pos.y})
		print("CONTACT_SHADOW_SAMPLE height %.2f visible %s alpha %.3f screen_sep %.1f" % [h, str(visible), alpha, screen_separation])
	_evaluate()

func _evaluate() -> void:
	print("CONTACT_SHADOW_DIAG_START")
	if results.size() < 4:
		push_error("CONTACT_SHADOW_FAIL: insufficient samples")
		get_tree().quit(1)
		return
	var ground := results[0]
	var low := results[1]
	var mid := results[2]
	var high := results[3]
	var reasons: Array[String] = []
	# Ground shadow should be visible and opaque
	if not ground.visible or ground.alpha < 0.18:
		reasons.append("ground not visible/opaque alpha %.3f" % ground.alpha)
	# High shadow should be faded or invisible (restrained blob)
	if high.visible and high.alpha > 0.12:
		reasons.append("high shadow not faded alpha %.3f >0.12" % high.alpha)
	# Alpha should decrease with height
	if not (ground.alpha > low.alpha and low.alpha > mid.alpha):
		reasons.append("alpha not decreasing with height %.3f %.3f %.3f" % [ground.alpha, low.alpha, mid.alpha])
	# Screen separation should increase with height (height cue)
	if not (high.screen_sep > low.screen_sep and low.screen_sep > ground.screen_sep - 1.0):
		# Allow small tolerance for ground
		reasons.append("screen separation not increasing %.1f %.1f %.1f" % [ground.screen_sep, low.screen_sep, high.screen_sep])
	# Shadow should be directly beneath (XZ distance small)
	for r in results:
		var shadow := skier.get_node_or_null("ContactShadow") as MeshInstance3D
		if shadow != null:
			var horiz := Vector2(skier.global_position.x - shadow.global_position.x, skier.global_position.z - shadow.global_position.z).length()
			# Allow 2.0m horizontal offset due to slope projection (n has -0.3z component per meter height)
			if horiz > 2.5:
				reasons.append("shadow not beneath horiz %.2f at h %.1f" % [horiz, r.height])
				break
	if reasons.is_empty():
		print("CONTACT_SHADOW_PASS: ground alpha %.3f high alpha %.3f sep %.1f->%.1f" % [ground.alpha, high.alpha, ground.screen_sep, high.screen_sep])
		# Save viewport image for review
		var tex := viewport.get_texture() if viewport != null else null
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				img.convert(Image.FORMAT_RGBA8)
				img.save_png("user://contact_shadow_capture.png")
				print("CONTACT_SHADOW_IMAGE_SAVED: user://contact_shadow_capture.png")
		get_tree().quit(0)
	else:
		for r in reasons:
			push_error("CONTACT_SHADOW_FAIL: " + r)
		get_tree().quit(1)
