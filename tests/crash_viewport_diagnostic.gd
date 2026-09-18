extends Node

# Viewport diagnostic for crash equipment: verifies that bail does not produce
# vertical skis, intersecting skis, or a frozen settle.

const RuntimeEnvironment := preload("res://util/runtime_environment.gd")

var resort: Node3D
var skier: SkierController
var viewport: SubViewport
var samples: Array[Dictionary] = []
var frame_count := 0
var crash_triggered := false
var _finish_started := false
var _evaluation_reasons: Array[String] = []
var _evaluation_summary := ""
var _waiting_for_clip := false
var _evaluation_started := false
var _crash_elapsed := 0.0
var _grounded_crash_elapsed := 0.0
var _post_recovery_frames := 0
var _saw_fall := false
var _saw_rest := false
var _saw_recovery := false
var _time_to_control := -1.0

const MAX_DIAGNOSTIC_SECONDS := 8.0
const MAX_SEVERE_TIME_TO_CONTROL_SECONDS := 3.5
const POST_RECOVERY_OBSERVATION_FRAMES := 12
const SKI_PLANE_ACQUISITION_SECONDS := 0.12
const MAX_GROUNDED_SKI_VERTICALITY := 0.70

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
		_finish(1)
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
	if not RuntimeEnvironment.is_headless():
		# Cap rendering for a watchable debug clip and extend the evaluation so
		# the recording contains FALL, REST, and recovery before the test exits.
		Engine.max_fps = 60
		ClipRecorder.clip_saved.connect(_on_clip_saved)
		ClipRecorder.clip_failed.connect(_on_clip_failed)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	frame_count += 1
	if frame_count == 30 and not crash_triggered:
		_trigger_crash()
		crash_triggered = true
	if not crash_triggered:
		return
	_crash_elapsed += delta
	_sample(delta)
	var stage := skier.crash_context.stage if skier.crash_context != null else CrashContext.Stage.NONE
	_saw_fall = _saw_fall or stage == CrashContext.Stage.FALL
	_saw_rest = _saw_rest or stage == CrashContext.Stage.REST
	_saw_recovery = _saw_recovery or stage == CrashContext.Stage.RECOVERY
	if _time_to_control < 0.0 and _saw_recovery and skier.state == SkierController.State.GROUND:
		_time_to_control = _crash_elapsed
	if _saw_recovery and skier.state == SkierController.State.GROUND:
		_post_recovery_frames += 1
	else:
		_post_recovery_frames = 0
	if _post_recovery_frames >= POST_RECOVERY_OBSERVATION_FRAMES:
		_evaluate()
	elif _crash_elapsed >= MAX_DIAGNOSTIC_SECONDS:
		_evaluation_reasons.append("crash lifecycle did not recover to GROUND within %.1f seconds" % MAX_DIAGNOSTIC_SECONDS)
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
	if not RuntimeEnvironment.is_headless():
		ClipRecorder._start_recording()

func _sample(delta: float) -> void:
	if skier == null or skier.animation_controller == null:
		return
	var left_ski := skier.animation_controller.left_ski as Node3D
	var right_ski := skier.animation_controller.right_ski as Node3D
	var pelvis := skier.animation_controller.pelvis as Node3D
	if left_ski == null or right_ski == null:
		return
	var left_forward := -left_ski.global_basis.z
	var right_forward := -right_ski.global_basis.z
	var ragdoll := ((skier.telemetry().crash as Dictionary).get("ragdoll", {}) as Dictionary)
	var left_released := bool(ragdoll.get("left_ski_released", false))
	var right_released := bool(ragdoll.get("right_ski_released", false))
	var grounded := skier.contact.grounded if skier.contact != null else false
	_grounded_crash_elapsed = _grounded_crash_elapsed + delta if grounded else 0.0
	var support_normal := skier.contact.average_normal if grounded and skier.contact.average_normal.length_squared() > 0.0001 else skier.crash_context.impact_normal
	support_normal = support_normal.normalized() if support_normal.is_finite() and support_normal.length_squared() > 0.0001 else Vector3.UP
	# A ski post has its long axis aligned with the live snow normal.
	# A released ski is intentionally independent debris and no longer part of
	# the skier's grounded silhouette contract.
	var left_vertical := 0.0 if left_released else absf(left_forward.normalized().dot(support_normal))
	var right_vertical := 0.0 if right_released else absf(right_forward.normalized().dot(support_normal))
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
		"grounded": grounded,
		"grounded_elapsed": _grounded_crash_elapsed,
		"support_normal": support_normal,
		"elapsed": skier.crash_context.elapsed if skier.crash_context != null else 0.0,
	})

func _evaluate() -> void:
	if _evaluation_started:
		return
	_evaluation_started = true
	print("CRASH_VIEWPORT_DIAG_START")
	if samples.is_empty():
		push_error("CRASH_DIAG_FAIL: no samples")
		_finish(1)
		return
	var max_vertical := 0.0
	var grounded_vertical_frames := 0
	var grounded_vertical_streak := 0
	var longest_vertical_streak := 0
	var grounded_frames := 0
	var grounded_streak := 0
	var longest_grounded_streak := 0
	var min_dist := 1e9
	var max_dist := 0.0
	var max_settled_angular := 0.0
	var saw_settled_angular_sample := false
	var finite_telemetry := true
	for s in samples:
		max_vertical = max(max_vertical, float(s.max_vertical))
		finite_telemetry = finite_telemetry and is_finite(float(s.max_vertical)) and is_finite(float(s.dist)) and is_finite(float(s.velocity)) and is_finite(float(s.angular)) and (s.pelvis as Vector3).is_finite() and (s.support_normal as Vector3).is_finite()
		if bool(s.grounded):
			grounded_frames += 1
			grounded_streak += 1
			longest_grounded_streak = maxi(longest_grounded_streak, grounded_streak)
		else:
			grounded_streak = 0
		var constrained_stage := int(s.stage) in [CrashContext.Stage.FALL, CrashContext.Stage.REST]
		var acquired_contact := float(s.grounded_elapsed) >= SKI_PLANE_ACQUISITION_SECONDS
		if float(s.max_vertical) > MAX_GROUNDED_SKI_VERTICALITY and bool(s.grounded) and constrained_stage and acquired_contact:
			grounded_vertical_frames += 1
			grounded_vertical_streak += 1
			longest_vertical_streak = maxi(longest_vertical_streak, grounded_vertical_streak)
		else:
			grounded_vertical_streak = 0
		if bool(s.grounded) and constrained_stage and float(s.grounded_elapsed) >= 0.5:
			max_settled_angular = maxf(max_settled_angular, float(s.angular))
			saw_settled_angular_sample = true
		min_dist = min(min_dist, float(s.dist))
		max_dist = max(max_dist, float(s.dist))
	print("CRASH_MAX_VERTICAL: %.3f grounded_fall_rest_vertical %d longest_streak %d (limit %.2f after %.2fs)" % [max_vertical, grounded_vertical_frames, longest_vertical_streak, MAX_GROUNDED_SKI_VERTICALITY, SKI_PLANE_ACQUISITION_SECONDS])
	print("CRASH_SKI_DIST_MIN: %.3f max %.3f" % [min_dist, max_dist])
	print("CRASH_GROUNDED_FRAMES: %d longest_streak %d" % [grounded_frames, longest_grounded_streak])
	print("CRASH_SETTLED_ANGULAR_MAX: %.3f rad/s after 0.5s" % max_settled_angular)
	print("CRASH_TIME_TO_CONTROL: %.3f s (limit %.2f)" % [_time_to_control, MAX_SEVERE_TIME_TO_CONTROL_SECONDS])
	# Check for static settling: after 60 frames post-impact, pelvis should still show small movement if dragging works.
	var early_pelvis: Vector3 = samples[mini(10, samples.size() - 1)].pelvis as Vector3
	var mid_pelvis: Vector3 = samples[mini(80, samples.size() - 1)].pelvis as Vector3
	var late_pelvis: Vector3 = samples[maxi(samples.size() - 10, 0)].pelvis as Vector3
	var early_to_mid := early_pelvis.distance_to(mid_pelvis)
	var mid_to_late := mid_pelvis.distance_to(late_pelvis)
	print("CRASH_PELVIS_EARLY_MID: %.4f mid_late %.4f" % [early_to_mid, mid_to_late])
	var reasons: Array[String] = _evaluation_reasons.duplicate()
	if grounded_vertical_frames > 0:
		reasons.append("vertical ski exceeded %.2f for %d grounded FALL/REST frames (longest streak %d, max %.3f)" % [MAX_GROUNDED_SKI_VERTICALITY, grounded_vertical_frames, longest_vertical_streak, max_vertical])
	if not _saw_fall or not _saw_rest or not _saw_recovery or skier.state != SkierController.State.GROUND:
		reasons.append("crash lifecycle was incomplete (fall=%s rest=%s recovery=%s state=%d)" % [_saw_fall, _saw_rest, _saw_recovery, skier.state])
	elif _time_to_control < 0.0 or _time_to_control > MAX_SEVERE_TIME_TO_CONTROL_SECONDS:
		reasons.append("severe crash returned control in %.3f s (limit %.2f s)" % [_time_to_control, MAX_SEVERE_TIME_TO_CONTROL_SECONDS])
	if not finite_telemetry:
		reasons.append("crash diagnostic produced non-finite telemetry")
	if not saw_settled_angular_sample:
		reasons.append("crash diagnostic did not observe grounded FALL/REST after 0.5 seconds")
	elif max_settled_angular > 1.8:
		reasons.append("grounded crash retained %.3f rad/s after 0.5 seconds" % max_settled_angular)
	if min_dist < 0.08:
		reasons.append("skis intersect dist %.3f <0.08" % min_dist)
	# Settling should not be frozen: mid->late should still have small motion, but early->mid should be larger
	if mid_to_late < 0.015:
		reasons.append("settling frozen mid->late %.4f <0.015" % mid_to_late)
	if early_to_mid < 0.04:
		reasons.append("no initial drag early->mid %.4f <0.04" % early_to_mid)
	# Image capture is supplemental on GPU and intentionally skipped in headless
	# mode so a dummy texture cannot mask the geometry-only crash checks.
	if RuntimeEnvironment.is_headless():
		print("CRASH_IMAGE_SKIP: geometry-only headless renderer")
	else:
		var tex := viewport.get_texture() if viewport != null else null
		var img := tex.get_image() if tex != null else null
		if img == null or img.is_empty():
			push_error("CRASH_VIEWPORT_FAIL: GPU viewport image was empty")
			reasons.append("GPU viewport image was empty")
		else:
			img.convert(Image.FORMAT_RGBA8)
			var save_error := img.save_png("user://crash_viewport_capture.png")
			if save_error != OK:
				reasons.append("could not save GPU viewport image")
			else:
				print("CRASH_IMAGE_SAVED: user://crash_viewport_capture.png")
	_evaluation_reasons = reasons
	_evaluation_summary = "vertical %.3f angular %.3f dist %.3f drag %.4f/%.4f" % [max_vertical, max_settled_angular, min_dist, early_to_mid, mid_to_late]
	if not RuntimeEnvironment.is_headless() and ClipRecorder.is_recording():
		_waiting_for_clip = true
		ClipRecorder._stop_recording()
		return
	_complete_evaluation()

func _on_clip_saved(path: String) -> void:
	if not _waiting_for_clip:
		return
	_waiting_for_clip = false
	print("CRASH_CLIP_SAVED: %s" % path)
	_complete_evaluation()

func _on_clip_failed(reason: String) -> void:
	if not _waiting_for_clip:
		return
	_waiting_for_clip = false
	_evaluation_reasons.append("could not encode crash clip: " + reason)
	_complete_evaluation()

func _complete_evaluation() -> void:
	if _evaluation_reasons.is_empty():
		print("CRASH_VIEWPORT_PASS: " + _evaluation_summary)
		_finish(0)
		return
	for reason: String in _evaluation_reasons:
		push_error("CRASH_VIEWPORT_FAIL: " + reason)
	_finish(1)

func _finish(exit_code: int) -> void:
	if _finish_started:
		return
	_finish_started = true
	set_process(false)
	set_physics_process(false)
	if is_instance_valid(ClipRecorder) and ClipRecorder.has_method("_shutdown_capture_workers"):
		ClipRecorder.call("_shutdown_capture_workers")
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
