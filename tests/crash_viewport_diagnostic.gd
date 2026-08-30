extends Node

# Viewport diagnostic for crash equipment: verifies that bail does not produce
# vertical skis, intersecting skis, or a frozen settle.

var resort: Node3D
var skier: SkierController
var viewport: SubViewport
var samples: Array[Dictionary] = []
var frame_count := 0
var crash_triggered := false

func _ready() -> void:
	resort = load("res://world/resort.tscn").instantiate() as Node3D
	add_child(resort)
	await get_tree().process_frame
	await get_tree().process_frame
	skier = resort.get_node_or_null("Skier") as SkierController
	if skier == null:
		skier = resort.find_children("*", "SkierController", true, false).front() as SkierController
	if skier == null:
		push_error("CRASH_DIAG_FAIL: skier not found")
		get_tree().quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_3d = get_viewport().world_3d
	add_child(viewport)
	var cam := Camera3D.new()
	viewport.add_child(cam)
	cam.current = true
	# Position camera to view crash from side (as in 29.5s clip)
	var n := preload("res://world/park_features/park_layout.gd").snow_normal()
	var down := preload("res://world/park_features/park_layout.gd").downhill()
	var focus := preload("res://world/park_features/park_layout.gd").snow_at(0.0, -10.0) + n * 0.5
	var cam_pos := focus - down * 6.0 + Vector3(5.5, 2.2, 0) + n * 1.8
	cam.look_at_from_position(cam_pos, focus, n)
	cam.fov = 72.0
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count == 30 and not crash_triggered:
		_trigger_crash()
		crash_triggered = true
	if not crash_triggered:
		return
	if frame_count > 30 and frame_count < 220:
		_sample()
	if frame_count == 220:
		_evaluate()

func _trigger_crash() -> void:
	# Place skier in air with high angular velocity and lateral bias, then force bail on landing.
	# Use more extreme values to reproduce the vertical-ski case from 29.5s clip.
	skier.global_position = preload("res://world/park_features/park_layout.gd").snow_at(0.0, 8.0) + Vector3(0, 3.5, 0)
	skier.velocity = Vector3(1.2, -7.5, -8.0)
	skier.angular_velocity = Vector3(3.2, 2.8, 4.2)
	# Start moderately tilted to reproduce the failed flip, but allow recovery.
	skier.global_basis = Basis.from_euler(Vector3(PI * 0.35, 0.0, PI * 0.22))
	skier.state = SkierController.State.AIR
	skier.air_time = 0.6
	# Trigger a crash via landing with high impact
	var ctx := CrashContext.new()
	ctx.begin(
		CrashContext.Reason.LANDING_IMPACT,
		CrashContext.Source.LANDING,
		SkierController.State.AIR,
		skier.velocity,
		skier.velocity,
		Vector3.UP,
		8.5,
		skier.angular_velocity.length(),
		0.65,
		0.0,
		1.0
	)
	skier.enter_crash(ctx)

func _sample() -> void:
	if skier == null or skier.animation_controller == null:
		return
	var left_ski := skier.animation_controller.left_ski as Node3D
	var right_ski := skier.animation_controller.right_ski as Node3D
	var pelvis := skier.animation_controller.pelvis as Node3D
	if left_ski == null or right_ski == null:
		return
	var left_global_up := left_ski.global_basis.y
	var right_global_up := right_ski.global_basis.y
	var left_forward := -left_ski.global_basis.z
	var right_forward := -right_ski.global_basis.z
	# Vertical ski: ski long axis (forward) dot world up near 1 means vertical post
	var left_vertical := absf(left_forward.dot(Vector3.UP))
	var right_vertical := absf(right_forward.dot(Vector3.UP))
	var dist_between_skis := left_ski.global_position.distance_to(right_ski.global_position)
	var pelvis_pos := pelvis.global_position if pelvis != null else skier.global_position
	samples.append({
		"frame": frame_count,
		"left_vertical": left_vertical,
		"right_vertical": right_vertical,
		"max_vertical": max(left_vertical, right_vertical),
		"dist": dist_between_skis,
		"pelvis": pelvis_pos,
		"velocity": skier.velocity.length(),
		"angular": skier.angular_velocity.length(),
		"stage": skier.crash_context.stage if skier.crash_context != null else 0,
		"grounded": skier.contact.grounded if skier.contact != null else false,
		"elapsed": skier.crash_context.elapsed if skier.crash_context != null else 0.0,
	})

func _evaluate() -> void:
	print("CRASH_VIEWPORT_DIAG_START")
	if samples.is_empty():
		push_error("CRASH_DIAG_FAIL: no samples")
		get_tree().quit(1)
		return
	var max_vertical := 0.0
	var grounded_vertical_frames := 0
	var min_dist := 1e9
	var max_dist := 0.0
	for s in samples:
		max_vertical = max(max_vertical, float(s.max_vertical))
		# Only count sustained vertical when grounded in REST (where skis should be flat, not post)
		if float(s.max_vertical) > 0.78 and bool(s.grounded) and int(s.stage) == CrashContext.Stage.REST:
			grounded_vertical_frames += 1
		min_dist = min(min_dist, float(s.dist))
		max_dist = max(max_dist, float(s.dist))
	print("CRASH_MAX_VERTICAL: %.3f grounded_rest_vertical %d (threshold <4)" % [max_vertical, grounded_vertical_frames])
	print("CRASH_SKI_DIST_MIN: %.3f max %.3f" % [min_dist, max_dist])
	# Check for static settling: after 60 frames post-impact, pelvis should still show small movement if dragging works.
	var early_pelvis: Vector3 = samples[10].pelvis as Vector3
	var mid_pelvis: Vector3 = samples[80].pelvis as Vector3
	var late_pelvis: Vector3 = samples[samples.size() - 10].pelvis as Vector3
	var early_to_mid := early_pelvis.distance_to(mid_pelvis)
	var mid_to_late := mid_pelvis.distance_to(late_pelvis)
	print("CRASH_PELVIS_EARLY_MID: %.4f mid_late %.4f" % [early_to_mid, mid_to_late])
	var reasons: Array[String] = []
	if grounded_vertical_frames > 4:
		reasons.append("vertical ski grounded_rest %d frames >4 (max %.3f)" % [grounded_vertical_frames, max_vertical])
	if min_dist < 0.08:
		reasons.append("skis intersect dist %.3f <0.08" % min_dist)
	# Settling should not be frozen: mid->late should still have small motion, but early->mid should be larger
	if mid_to_late < 0.015:
		reasons.append("settling frozen mid->late %.4f <0.015" % mid_to_late)
	if early_to_mid < 0.04:
		reasons.append("no initial drag early->mid %.4f <0.04" % early_to_mid)
	# Image capture for manual review
	var tex := viewport.get_texture() if viewport != null else null
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			img.save_png("user://crash_viewport_capture.png")
			print("CRASH_IMAGE_SAVED: user://crash_viewport_capture.png")
	if reasons.is_empty():
		print("CRASH_VIEWPORT_PASS: vertical %.3f dist %.3f drag %.4f/%.4f" % [max_vertical, min_dist, early_to_mid, mid_to_late])
		get_tree().quit(0)
	else:
		for r in reasons:
			push_error("CRASH_VIEWPORT_FAIL: " + r)
		get_tree().quit(1)
