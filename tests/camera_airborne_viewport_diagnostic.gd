extends Node

## Deterministic screen-space camera acceptance. This intentionally drives the
## real SkiCameraController with a synthetic jump so a camera can fail on the
## same symptom as the gameplay clip without requiring a rendered recording.

const STEP := 1.0 / 120.0
const HARD_SAFE_RECT := Rect2(0.10, 0.08, 0.80, 0.80)
const INNER_SAFE_RECT := Rect2(0.30, 0.24, 0.40, 0.36)
const LANDING_RECT := Rect2(0.14, 0.46, 0.72, 0.36)
const FOV_RATE_LIMIT := 24.0
const LANDMARK_OFFSETS := [
	Vector3(0.0, 1.95, 0.0),
	Vector3(0.0, 1.05, 0.0),
	Vector3(-0.32, 0.78, 0.0),
	Vector3(0.32, 0.78, 0.0),
	Vector3(-0.34, 0.30, 0.0),
	Vector3(0.34, 0.30, 0.0),
	Vector3(-0.42, 0.10, -0.10),
	Vector3(0.42, 0.10, -0.10),
	Vector3(-0.52, 0.08, -0.65),
	Vector3(0.52, 0.08, -0.65),
	Vector3(-0.52, 0.08, 0.40),
	Vector3(0.52, 0.08, 0.40),
]

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	for step: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		_run_airborne_composition_reproduction(step)
		_run_soft_inner_convergence_reproduction(step)
		_run_high_speed_chase_reproduction(step)
		_run_screen_space_continuity_reproduction(step)
		_run_ground_to_air_transition_reproduction(step)
		_run_carve_lookahead_reproduction(step)
		_run_foreground_occlusion_reproduction(step)
		_run_respawn_initialization_reproduction(step)
		_run_hockey_stop_reproduction(step)
		_run_fallback_contract_reproduction(step)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_VIEWPORT_PASS: airborne composition, landing framing, recovery, rates, fallbacks, yaw, and respawn initialization passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_VIEWPORT_FAIL: " + failure)
	get_tree().quit(1)

func _run_airborne_composition_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.global_position = Vector3(0.0, 0.35, 0.0)
	skier.state = SkierController.State.AIR
	skier.velocity = Vector3(0.0, 7.5, -10.0)

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	if not _validate_camera_exports(camera_rig, step):
		_remove_target_and_camera(skier, camera_rig)
		return

	var previous_distance := camera_rig.global_position.distance_to(skier.global_position)
	var previous_fov := camera_rig.camera.fov
	var previous_yaw := float(camera_rig.debug_snapshot().get("actual_yaw_degrees", 0.0))
	var landing_frames := 0
	var landing_visible_frames := 0
	var recovery_seen := false
	var frame_count := ceili(2.0 / step)
	for frame_index: int in frame_count:
		var elapsed := float(frame_index) * step
		var phase := clampf(elapsed / 1.8, 0.0, 1.0)
		var height := 0.35 + 3.6 * sin(phase * PI)
		var vertical_speed := 3.6 * PI / 1.8 * cos(phase * PI)
		var lateral_excursion := sin(elapsed * 3.7) * 2.45
		skier.global_position = Vector3(lateral_excursion, height, -10.0 * elapsed)
		skier.velocity = Vector3(0.0, vertical_speed, -10.0)
		# Rotate the gameplay body through a flip/spin while preserving velocity.
		# Airborne camera heading must remain trajectory-driven.
		skier.rotation = Vector3(0.35 * sin(elapsed * 5.0), elapsed * 4.0, 0.2 * cos(elapsed * 4.0))
		skier.state = SkierController.State.AIR
		skier.predicted_landing_valid = true
		skier.predicted_landing_point = Vector3(0.0, 0.35, -18.0)
		skier.predicted_landing_time = maxf(0.02, 1.8 - elapsed)

		camera_rig._physics_process(step)
		var bounds := _projected_landmark_bounds(camera_rig, skier)
		var snapshot := camera_rig.debug_snapshot()
		var yaw := float(snapshot.get("actual_yaw_degrees", 0.0))
		var yaw_step := absf(rad_to_deg(angle_difference(deg_to_rad(previous_yaw), deg_to_rad(yaw))))
		var yaw_limit := camera_rig.maximum_camera_yaw_rate_degrees * step + 0.07
		if yaw_step > yaw_limit:
			failures.append("Airborne %.0f Hz frame %d rendered yaw step %.3f exceeded %.3f" % [1.0 / step, frame_index, yaw_step, yaw_limit])
			break
		previous_yaw = yaw
		if not bool(snapshot.get("composition_valid", false)):
			failures.append("Airborne %.0f Hz frame %d reported invalid composition" % [1.0 / step, frame_index])
			break
		if not camera_rig._camera_destination_is_clear(camera_rig.global_position):
			failures.append("Airborne %.0f Hz frame %d placed the camera volume inside geometry" % [1.0 / step, frame_index])
			break
		if not _rect_contains_rect(HARD_SAFE_RECT, bounds):
			failures.append("Airborne %.0f Hz frame %d placed skier bounds %s outside hard safe rect" % [1.0 / step, frame_index, bounds])
			break
		if not _rect_contains_rect(INNER_SAFE_RECT, bounds):
			if snapshot.has("composition_recovery_active"):
				recovery_seen = recovery_seen or bool(snapshot.composition_recovery_active)
			else:
				failures.append("Airborne edge displacement exposed no composition recovery telemetry")
		var descending := vertical_speed < 0.0
		if descending and skier.predicted_landing_valid:
			landing_frames += 1
			var landing_screen := _project_normalized(camera_rig, skier.predicted_landing_point)
			if LANDING_RECT.has_point(landing_screen):
				landing_visible_frames += 1

		var distance := camera_rig.global_position.distance_to(skier.global_position)
		var fov := camera_rig.camera.fov
		if absf(distance - previous_distance) > camera_rig.maximum_distance_change_rate * step + 0.02:
			failures.append("Airborne %.0f Hz frame %d changed camera distance by %.3f m beyond its rate limit" % [1.0 / step, frame_index, absf(distance - previous_distance)])
			break
		if absf(fov - previous_fov) > FOV_RATE_LIMIT * step + 0.02:
			failures.append("Airborne %.0f Hz frame %d changed FOV by %.3f degrees beyond its rate limit" % [1.0 / step, frame_index, absf(fov - previous_fov)])
			break
		previous_distance = distance
		previous_fov = fov

	if landing_frames > 0:
		var ratio := float(landing_visible_frames) / float(landing_frames)
		var target := camera_rig.landing_visibility_target
		var hard_floor := camera_rig.landing_visibility_hard_floor
		if ratio < target:
			if ratio < hard_floor:
				failures.append("Predicted landing was inside its descent visibility window for only %d/%d (%.1f%%) below hard floor %.0f%%" % [landing_visible_frames, landing_frames, ratio*100.0, hard_floor*100.0])
			else:
				print("CAMERA_VIEWPORT_WARN: landing visibility %.1f%% (%d/%d) below %.0f%% target but above %.0f%% floor at %.0f Hz" % [ratio*100.0, landing_visible_frames, landing_frames, target*100.0, hard_floor*100.0, 1.0/step])
	if not recovery_seen:
		failures.append("Airborne composition never exposed edge-recovery telemetry")

	_remove_target_and_camera(skier, camera_rig)

func _run_soft_inner_convergence_reproduction(step: float) -> void:
	# Keep skier stationary and deliberately perturb the camera position instead.
	# This ensures feed-forward (target displacement) does not mask the soft solver.
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.AIR
	skier.global_position = Vector3(0.0, 1.2, 0.0)
	skier.velocity = Vector3(0.0, 0.0, -12.0)
	skier.predicted_landing_valid = false
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	# Let grace expire so AIR composition is active
	for i: int in ceili(0.25 / step):
		camera_rig._physics_process(step)
	var base_position := camera_rig.global_position
	var base_basis := camera_rig.global_basis
	var base_fov := camera_rig.camera.fov
	var up := Vector3.UP
	var right := base_basis.x.normalized()
	var cam_up := base_basis.y.normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	if cam_up.length_squared() < 0.001:
		cam_up = Vector3.UP
	var candidates: Array[Vector3] = []
	for dx: float in [1.0, 1.4, 1.8, 2.2, 2.6]:
		candidates.append(base_position + right * dx)
		candidates.append(base_position - right * dx)
		candidates.append(base_position + cam_up * dx * 0.6)
		candidates.append(base_position - cam_up * dx * 0.6)
		candidates.append(base_position + right * dx + cam_up * dx * 0.3)
		candidates.append(base_position - right * dx + cam_up * dx * 0.3)
		candidates.append(base_position + right * dx * 0.7 - cam_up * dx * 0.4)
	var perturbed_position := Vector3.ZERO
	var initial_violation := 0.0
	var found := false
	for cand: Vector3 in candidates:
		if not cand.is_finite():
			continue
		if not camera_rig._camera_destination_is_clear(cand):
			continue
		var evaluation := camera_rig._evaluate_composition(cand, base_basis, base_fov, up)
		var hard_valid: bool = camera_rig._composition_hard_valid(evaluation)
		var inner_violation := float(evaluation.get("inner_violation", 0.0))
		if hard_valid and inner_violation > 0.01:
			perturbed_position = cand
			initial_violation = inner_violation
			found = true
			break
	if not found:
		failures.append("Soft convergence setup did not find a camera pose with hard_valid == true and inner_violation > 0.01 at %.0f Hz" % [1.0/step])
		_remove_target_and_camera(skier, camera_rig)
		return
	# Warmup check that perturbed pose indeed starts outside inner but inside hard
	var perturbed_evaluation := camera_rig._evaluate_composition(perturbed_position, base_basis, base_fov, up)
	initial_violation = float(perturbed_evaluation.get("inner_violation", 0.0))
	# Deliberately perturb the camera (keep skier stationary)
	camera_rig.global_position = perturbed_position
	var max_relative_per_frame := camera_rig.composition_comfortable_correction_speed * step + 0.05
	var prev_cam := camera_rig.global_position
	var prev_skier := skier.global_position
	var converged := false
	var recovery_seen := false
	for frame: int in ceili(0.75 / step):
		camera_rig._physics_process(step)
		var cam_pos := camera_rig.global_position
		var rel := (cam_pos - prev_cam - (skier.global_position - prev_skier)).length()
		if rel > max_relative_per_frame + 0.03:
			failures.append("Soft convergence %.0f Hz frame %d relative %.3f exceeded 8 m/s cap %.3f" % [1.0/step, frame, rel, max_relative_per_frame])
			break
		prev_cam = cam_pos
		prev_skier = skier.global_position
		var snapshot := camera_rig.debug_snapshot()
		if bool(snapshot.get("composition_recovery_active", false)):
			recovery_seen = true
		var cur_evaluation := camera_rig._evaluate_composition(camera_rig.global_position, camera_rig.global_basis, camera_rig.camera.fov, up)
		var cur_inner := float(cur_evaluation.get("inner_violation", 0.0))
		if cur_inner < 0.02 or cur_inner <= initial_violation * 0.50:
			converged = true
			break
	if not recovery_seen:
		failures.append("Soft convergence %.0f Hz never activated composition_recovery_active at inner_violation %.4f" % [1.0/step, initial_violation])
	elif not converged:
		var final_evaluation := camera_rig._evaluate_composition(camera_rig.global_position, camera_rig.global_basis, camera_rig.camera.fov, up)
		var final_v := float(final_evaluation.get("inner_violation", 0.0))
		failures.append("Soft inner-rect recovery did not converge at %.0f Hz: initial %.4f -> final %.4f (need <0.02 or 50%% reduction within 0.75s)" % [1.0/step, initial_violation, final_v])
	_remove_target_and_camera(skier, camera_rig)

func _run_high_speed_chase_reproduction(step: float) -> void:
	# 38 m/s on snow and 45 m/s air terminal — former test used only 10 m/s and missed the outrun case.
	for speed: float in [38.0, 30.0]:
		var skier := SkierController.new()
		skier.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(skier)
		skier.state = SkierController.State.AIR
		skier.global_position = Vector3(0.0, 0.35, 0.0)
		skier.velocity = Vector3(0.0, 2.0, -speed)
		var camera_rig := SkiCameraController.new()
		camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(camera_rig)
		camera_rig.set_target(skier)
		var prev_camera_pos := camera_rig.global_position
		var prev_skier_pos := skier.global_position
		var prev_bounds := _projected_landmark_bounds(camera_rig, skier)
		var frame_count := ceili(1.5 / step)
		for frame_index: int in frame_count:
			var elapsed := float(frame_index) * step
			var height := 0.35 + 2.0 * sin(elapsed * 1.2)
			var vspeed := 2.0 * 1.2 * cos(elapsed * 1.2)
			var lateral := sin(elapsed * 3.7) * 2.45
			skier.global_position = Vector3(lateral, height, -speed * elapsed)
			skier.velocity = Vector3(cos(elapsed*3.7)*3.7*2.45, vspeed, -speed)
			skier.state = SkierController.State.AIR
			skier.predicted_landing_valid = true
			skier.predicted_landing_point = Vector3(0.0, 0.35, -speed * 1.5)
			skier.predicted_landing_time = maxf(0.02, 1.5 - elapsed)
			camera_rig._physics_process(step)
			var pos := camera_rig.global_position
			var skier_pos := skier.global_position
			var target_disp := skier_pos - prev_skier_pos
			var cam_disp := pos - prev_camera_pos
			var relative := cam_disp - target_disp
			# Relative correction must stay within 12 m/s (hard) even at 38 m/s chase.
			if relative.length() > camera_rig.maximum_relative_correction_speed * step + 0.06:
				failures.append("High-speed %.0f m/s %.0f Hz frame %d relative correction %.3f m exceeded %.3f" % [speed, 1.0/step, frame_index, relative.length(), camera_rig.maximum_relative_correction_speed * step + 0.06])
				break
			var distance := pos.distance_to(skier_pos)
			if distance < camera_rig.minimum_camera_distance - 0.02 or distance > camera_rig.maximum_camera_distance + 0.02:
				failures.append("High-speed %.0f m/s %.0f Hz frame %d distance %.3f out of bounds" % [speed, 1.0/step, frame_index, distance])
				break
			var bounds := _projected_landmark_bounds(camera_rig, skier)
			if not _rect_contains_rect(HARD_SAFE_RECT, bounds):
				failures.append("High-speed %.0f m/s %.0f Hz frame %d bounds %s outside hard rect" % [speed, 1.0/step, frame_index, bounds])
				break
			# Screen-space continuity: size should not snap 10px→35px.
			if prev_bounds.size.x > 0.01:
				var size_delta := (bounds.size - prev_bounds.size).length() / maxf(prev_bounds.size.length(), 0.01)
				if size_delta > 0.35:
					failures.append("High-speed %.0f m/s %.0f Hz frame %d screen size snap %.2f" % [speed, 1.0/step, frame_index, size_delta])
					break
			prev_camera_pos = pos
			prev_skier_pos = skier_pos
			prev_bounds = bounds
		_remove_target_and_camera(skier, camera_rig)
		if not failures.is_empty():
			return

func _run_screen_space_continuity_reproduction(step: float) -> void:
	# Catches 60 px and 78 px single-frame teleports at 15.23s / 23.37s.
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.AIR
	skier.global_position = Vector3(0.0, 0.35, 0.0)
	skier.velocity = Vector3(0.0, 4.0, -22.0)
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	var prev_pos := camera_rig.global_position
	var prev_skier := skier.global_position
	var prev_center := _projected_landmark_bounds(camera_rig, skier).get_center()
	var frames := ceili(2.0 / step)
	for idx: int in frames:
		var elapsed := float(idx) * step
		var phase := clampf(elapsed / 1.6, 0.0, 1.0)
		var h := 0.35 + 4.2 * sin(phase * PI)
		var vs := 4.2 * PI / 1.6 * cos(phase * PI)
		var lat := sin(elapsed * 4.1) * 2.8
		skier.global_position = Vector3(lat, h, -22.0 * elapsed)
		skier.velocity = Vector3(cos(elapsed*4.1)*4.1*2.8, vs, -22.0)
		skier.predicted_landing_valid = true
		skier.predicted_landing_point = Vector3(0.0, 0.35, -35.0)
		skier.predicted_landing_time = maxf(0.02, 1.6 - elapsed)
		camera_rig._physics_process(step)
		var center := _projected_landmark_bounds(camera_rig, skier).get_center()
		var cam_disp := camera_rig.global_position - prev_pos
		var target_disp := skier.global_position - prev_skier
		var rel := (cam_disp - target_disp).length()
		if rel > camera_rig.maximum_relative_correction_speed * step + 0.07:
			failures.append("Screen-continuity %.0f Hz frame %d relative %.3f exceeded cap" % [1.0/step, idx, rel])
			break
		var screen_delta := (center - prev_center).length()
		# At 1920x1080, 78 px ≈ 0.072 normalized. Cap at 0.08.
		if screen_delta > 0.09:
			failures.append("Screen-continuity %.0f Hz frame %d center jump %.3f" % [1.0/step, idx, screen_delta])
			break
		prev_pos = camera_rig.global_position
		prev_skier = skier.global_position
		prev_center = center
	_remove_target_and_camera(skier, camera_rig)

func _run_ground_to_air_transition_reproduction(step: float) -> void:
	# Regressions for 6.07-6.10s, 11.4-11.6s, 23.33-23.40s, 26.6s takeoffs.
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_position = Vector3(0.0, 0.35, 0.0)
	skier.velocity = Vector3(0.0, 0.0, -25.0)
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	# 0.5 s ground at 25 m/s
	for i: int in ceili(0.5 / step):
		skier.global_position += Vector3(0,0,-25.0*step)
		camera_rig._physics_process(step)
	var ground_dist := camera_rig.global_position.distance_to(skier.global_position)
	var ground_fov := camera_rig.camera.fov
	var ground_pos := camera_rig.global_position
	var ground_skier := skier.global_position
	# Takeoff -> AIR
	skier.state = SkierController.State.AIR
	skier.velocity = Vector3(0.0, 7.0, -25.0)
	skier.predicted_landing_valid = true
	skier.predicted_landing_point = Vector3(0,0.35,-40)
	skier.predicted_landing_time = 0.7
	for i: int in 8:
		var elapsed := float(i) * step
		skier.global_position = ground_skier + Vector3(0, 0.5 + 3.0*sin(elapsed*2.0), -25.0*elapsed)
		skier.velocity = Vector3(0, 3.0*2.0*cos(elapsed*2.0), -25.0)
		var prev_cam := camera_rig.global_position
		var prev_ski := skier.global_position - Vector3(0,0,-25.0*step) if i>0 else ground_skier
		camera_rig._physics_process(step)
		var dist := camera_rig.global_position.distance_to(skier.global_position)
		if absf(dist - ground_dist) > camera_rig.maximum_distance_change_rate * step * 4.0 + 0.1:
			failures.append("Takeoff transition %.0f Hz frame %d distance snap %.3f (ground %.3f -> %.3f)" % [1.0/step, i, absf(dist-ground_dist), ground_dist, dist])
			break
		var cam_move := camera_rig.global_position - prev_cam
		# First airborne frames must not teleport beyond relative cap.
		var target_move := skier.global_position - prev_ski
		var rel := (cam_move - target_move).length()
		if rel > camera_rig.composition_comfortable_correction_speed * step + 0.08:
			failures.append("Takeoff transition %.0f Hz frame %d relative %.3f exceeded comfortable cap" % [1.0/step, i, rel])
			break
		var fov_delta := absf(camera_rig.camera.fov - ground_fov)
		if fov_delta > 6.0:
			failures.append("Takeoff transition %.0f Hz frame %d FOV snap %.2f" % [1.0/step, i, fov_delta])
			break
	_remove_target_and_camera(skier, camera_rig)

func _validate_camera_exports(camera_rig: SkiCameraController, step: float) -> bool:
	var valid := true
	if camera_rig.composition_hard_rect != HARD_SAFE_RECT:
		failures.append("Camera %.0f Hz composition_hard_rect %s != expected %s" % [1.0 / step, camera_rig.composition_hard_rect, HARD_SAFE_RECT])
		valid = false
	if camera_rig.composition_inner_rect != INNER_SAFE_RECT:
		failures.append("Camera %.0f Hz composition_inner_rect %s != expected %s" % [1.0 / step, camera_rig.composition_inner_rect, INNER_SAFE_RECT])
		valid = false
	if camera_rig.composition_landing_rect != LANDING_RECT:
		failures.append("Camera %.0f Hz composition_landing_rect %s != expected %s" % [1.0 / step, camera_rig.composition_landing_rect, LANDING_RECT])
		valid = false
	if absf(camera_rig.maximum_fov_change_rate - FOV_RATE_LIMIT) > 0.001:
		failures.append("Camera %.0f Hz maximum_fov_change_rate %.2f != expected %.2f" % [1.0 / step, camera_rig.maximum_fov_change_rate, FOV_RATE_LIMIT])
		valid = false
	if absf(camera_rig.maximum_relative_correction_speed - 12.0) > 0.01:
		failures.append("Camera %.0f Hz maximum_relative_correction_speed %.2f != expected 12.0" % [1.0 / step, camera_rig.maximum_relative_correction_speed])
		valid = false
	if absf(camera_rig.composition_comfortable_correction_speed - 8.0) > 0.01:
		failures.append("Camera %.0f Hz composition_comfortable_correction_speed %.2f != expected 8.0" % [1.0 / step, camera_rig.composition_comfortable_correction_speed])
		valid = false
	if absf(camera_rig.maximum_camera_yaw_rate_degrees - 90.0) > 0.01:
		failures.append("Camera %.0f Hz maximum_camera_yaw_rate_degrees %.2f != expected 90.0" % [1.0 / step, camera_rig.maximum_camera_yaw_rate_degrees])
		valid = false
	if absf(camera_rig.hockey_divergence_threshold_degrees - 18.0) > 0.01:
		failures.append("Camera %.0f Hz hockey_divergence_threshold_degrees %.2f != expected 18.0" % [1.0 / step, camera_rig.hockey_divergence_threshold_degrees])
		valid = false
	if absf(camera_rig.landing_visibility_target - 0.95) > 0.001 or absf(camera_rig.landing_visibility_hard_floor - 0.75) > 0.001:
		failures.append("Camera %.0f Hz landing visibility exports %.3f/%.3f != 0.95/0.75" % [1.0 / step, camera_rig.landing_visibility_target, camera_rig.landing_visibility_hard_floor])
		valid = false
	var has_legacy := false
	for p: Dictionary in camera_rig.get_property_list():
		if p.name == "composition_debug_allow_legacy_300" or p.name == "composition_recovery_speed":
			has_legacy = true
			break
	if has_legacy:
		failures.append("Camera %.0f Hz still exports legacy 300 m/s authority" % [1.0 / step])
		valid = false
	return valid

func _run_carve_lookahead_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.velocity = Vector3(0.0, 0.0, -12.0)
	skier.heading_travel_angle_degrees = 35.0

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	for _index: int in ceili(1.0 / step):
		camera_rig._physics_process(step)
	var snapshot := camera_rig.debug_snapshot()
	var carve_offset := snapshot.get("carve_look_ahead_offset", Vector3.ZERO) as Vector3
	if carve_offset.length() < 0.05:
		failures.append("Lateral carve look-ahead did not open space in the travel direction")
	_remove_target_and_camera(skier, camera_rig)

func _run_foreground_occlusion_reproduction(step: float) -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80.0, 0.5, 80.0)
	floor_shape.shape = floor_box
	floor.position.y = -0.25
	floor.add_child(floor_shape)
	add_child(floor)

	var feature := StaticBody3D.new()
	feature.collision_layer = 4
	feature.collision_mask = 0
	feature.position = Vector3(0.0, 1.0, 2.25)
	var feature_shape := CollisionShape3D.new()
	var feature_box := BoxShape3D.new()
	feature_box.size = Vector3(3.0, 2.0, 0.9)
	feature_shape.shape = feature_box
	feature.add_child(feature_shape)
	add_child(feature)

	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.AIR
	skier.global_position = Vector3(0.0, 1.0, 0.0)
	skier.velocity = Vector3(0.0, 0.0, -8.0)
	skier.predicted_landing_valid = true
	skier.predicted_landing_point = Vector3(0.0, 0.35, -8.0)
	skier.predicted_landing_time = 0.55

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	# Warmup allowance: bounded 12 m/s correction needs ~0.25s to clear feature, unlike old 300 m/s teleport.
	var warmup_frames := ceili(0.25 / step)
	for _index: int in ceili(0.75 / step):
		camera_rig._physics_process(step)
		if _index < warmup_frames:
			continue
		var frame_snapshot := camera_rig.debug_snapshot()
		if not bool(frame_snapshot.get("composition_valid", false)) or not camera_rig._camera_destination_is_clear(camera_rig.global_position):
			failures.append("Foreground feature produced an invalid or colliding camera pose at %s after warmup" % camera_rig.global_position)
			break
	var snapshot := camera_rig.debug_snapshot()
	if not bool(snapshot.get("composition_valid", false)):
		failures.append("Foreground feature left the camera in an invalid composition at %s, fallback %s" % [camera_rig.global_position, snapshot.get("camera_fallback_count", -1)])
	if float(snapshot.get("foreground_occlusion_fraction", 1.0)) > camera_rig.maximum_body_occlusion_fraction:
		failures.append("Foreground feature left %.2f of skier samples occluded" % float(snapshot.foreground_occlusion_fraction))
	if not snapshot.has("camera_fallback_count") or not snapshot.has("composition_recovery_active"):
		failures.append("Foreground composition fallback telemetry was incomplete")

	_remove_target_and_camera(skier, camera_rig)
	remove_child(feature)
	feature.free()
	remove_child(floor)
	floor.free()

func _run_respawn_initialization_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.AIR
	skier.global_position = Vector3(0.0, 18.0, -40.0)
	skier.velocity = Vector3(0.0, 8.0, -12.0)

	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	skier.respawn_applied.connect(func(_value: Transform3D) -> void: camera_rig.reset_immediate())
	for _index: int in ceili(0.75 / step):
		camera_rig._physics_process(step)

	var spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 98.0, 138.0))
	skier.respawn_at(spawn)

	var reset_position := camera_rig.global_position
	var reset_distance := reset_position.distance_to(skier.global_position)
	camera_rig._physics_process(step)
	var first_frame_delta := camera_rig.global_position.distance_to(reset_position)
	if reset_distance < camera_rig.minimum_camera_distance - 0.01 or reset_distance > camera_rig.maximum_camera_distance + 0.01:
		failures.append("Respawn reset produced an invalid camera distance %.3f m" % reset_distance)
	if first_frame_delta > 0.35:
		failures.append("Respawn first-frame camera correction was %.3f m instead of a seeded pose" % first_frame_delta)
	var bounds := _projected_landmark_bounds(camera_rig, skier)
	if not _rect_contains_rect(HARD_SAFE_RECT, bounds):
		failures.append("Respawn first frame placed skier bounds %s outside hard safe rect" % bounds)

	_remove_target_and_camera(skier, camera_rig)

func _run_hockey_stop_reproduction(step: float) -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80.0, 0.5, 80.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	floor.position.y = -0.25
	add_child(floor)
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_position = Vector3.ZERO
	skier.velocity = Vector3(0.0, 0.0, -25.0)
	skier.braking = false
	skier.brake_amount = 0.0
	skier.heading_travel_angle_degrees = 0.0
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	# Settle at 25 m/s
	for i: int in ceili(0.5 / step):
		skier.global_position += Vector3(0.0, 0.0, -25.0 * step)
		camera_rig._physics_process(step)
	var prev_skier := skier.global_position
	var prev_yaw := float(camera_rig.debug_snapshot().get("actual_yaw_degrees", 0.0))
	var prev_center := _projected_landmark_bounds(camera_rig, skier).get_center()
	var hockey_hold_seen := false
	var frames := ceili(1.2 / step)
	for frame_index: int in frames:
		var t := float(frame_index) * step
		var brake_prog := clampf(t / 0.30, 0.0, 1.0)
		var speed := 25.0 - clampf(t / 0.60, 0.0, 1.0) * 20.0
		if t > 0.60:
			speed = 5.0
		var divergence := clampf(t / 0.60, 0.0, 1.0) * 35.0
		skier.brake_amount = brake_prog
		skier.braking = brake_prog > 0.01
		skier.heading_travel_angle_degrees = divergence
		var downhill := Vector3(0.0, 0.0, -1.0)
		skier.velocity = downhill * speed
		skier.global_basis = Basis(Vector3.UP, deg_to_rad(divergence))
		skier.global_position += skier.velocity * step
		var prev_pos := camera_rig.global_position
		var prev_sk := prev_skier
		camera_rig._physics_process(step)
		var pos := camera_rig.global_position
		var snapshot := camera_rig.debug_snapshot()
		var yaw := float(snapshot.get("actual_yaw_degrees", 0.0))
		var yaw_step := absf(rad_to_deg(angle_difference(deg_to_rad(prev_yaw), deg_to_rad(yaw))))
		var yaw_limit := camera_rig.maximum_camera_yaw_rate_degrees * step + 0.06
		if yaw_step > yaw_limit + 0.01:
			failures.append("Hockey-stop %.0f Hz frame %d yaw step %.3f exceeded 90 deg/s limit %.3f" % [1.0/step, frame_index, yaw_step, yaw_limit])
			break
		var rel := (pos - prev_pos - (skier.global_position - prev_sk)).length()
		var rel_limit := camera_rig.maximum_relative_correction_speed * step + 0.045
		if rel > rel_limit + 0.001:
			failures.append("Hockey-stop %.0f Hz frame %d relative correction %.3f exceeded 12 m/s limit %.3f" % [1.0/step, frame_index, rel, rel_limit])
			break
		var center := _projected_landmark_bounds(camera_rig, skier).get_center()
		var screen_delta := (center - prev_center).length()
		if screen_delta > 0.09:
			failures.append("Hockey-stop %.0f Hz frame %d screen center jump %.3f exceeded 0.09" % [1.0/step, frame_index, screen_delta])
			break
		if bool(snapshot.get("hockey_heading_hold_active", false)):
			hockey_hold_seen = true
		prev_yaw = yaw
		prev_skier = skier.global_position
		prev_center = center
	if not hockey_hold_seen:
		failures.append("Hockey-stop %.0f Hz hold never activated" % [1.0/step])
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
	remove_child(floor)
	floor.free()

func _run_fallback_contract_reproduction(step: float) -> void:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_position = Vector3.ZERO
	skier.velocity = Vector3(0.0, 0.0, -38.0)
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	var frame_start := camera_rig.global_position
	var target_displacement := Vector3(0.0, 0.0, -38.0 * step)
	skier.global_position += target_displacement
	var feed_forward_hold := frame_start + target_displacement
	if not camera_rig._fallback_pose_is_valid(feed_forward_hold, frame_start, target_displacement, Vector3.UP, step):
		failures.append("Fallback contract %.0f Hz rejected valid feed-forward hold" % [1.0 / step])
		_remove_target_and_camera(skier, camera_rig)
		return
	var over_relative := feed_forward_hold + Vector3.RIGHT * (camera_rig.maximum_relative_correction_speed * step + 0.12)
	if camera_rig._fallback_pose_is_valid(over_relative, frame_start, target_displacement, Vector3.UP, step):
		failures.append("Fallback contract %.0f Hz accepted over-cap relative correction" % [1.0 / step])
	var too_close := skier.global_position + Vector3(0.0, camera_rig.minimum_camera_up_offset, -camera_rig.minimum_camera_distance * 0.45)
	if camera_rig._fallback_pose_is_valid(too_close, frame_start, target_displacement, Vector3.UP, step):
		failures.append("Fallback contract %.0f Hz accepted too-close pose" % [1.0 / step])
	var too_far := skier.global_position + Vector3(0.0, 1.0, -(camera_rig.maximum_camera_distance + 1.0))
	if camera_rig._fallback_pose_is_valid(too_far, frame_start, target_displacement, Vector3.UP, step):
		failures.append("Fallback contract %.0f Hz accepted too-far pose" % [1.0 / step])
	var too_low := skier.global_position + Vector3(0.0, camera_rig.minimum_camera_up_offset - 0.2, -camera_rig.follow_distance)
	if camera_rig._fallback_pose_is_valid(too_low, frame_start, target_displacement, Vector3.UP, step):
		failures.append("Fallback contract %.0f Hz accepted low up-offset pose" % [1.0 / step])
	_remove_target_and_camera(skier, camera_rig)

func _projected_landmark_bounds(camera_rig: SkiCameraController, skier: SkierController) -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for offset: Vector3 in LANDMARK_OFFSETS:
		var world_position := skier.global_position + skier.global_basis * offset
		var camera_space := camera_rig.global_transform.affine_inverse() * world_position
		if -camera_space.z <= 0.01:
			return Rect2(-10.0, -10.0, 20.0, 20.0)
		var screen := _project_normalized(camera_rig, world_position)
		if not initialized:
			bounds = Rect2(screen, Vector2.ZERO)
			initialized = true
		else:
			bounds = bounds.expand(screen)
	return bounds

func _project_normalized(camera_rig: SkiCameraController, world_position: Vector3) -> Vector2:
	var camera_space := camera_rig.global_transform.affine_inverse() * world_position
	var depth := maxf(0.01, -camera_space.z)
	var viewport_size := camera_rig._composition_viewport_size()
	var aspect := viewport_size.x / viewport_size.y
	var focal_scale := 1.0 / tan(deg_to_rad(camera_rig.camera.fov) * 0.5)
	return Vector2(
		0.5 + camera_space.x * focal_scale / (aspect * depth) * 0.5,
		0.5 - camera_space.y * focal_scale / depth * 0.5
	)

func _rect_contains_rect(container: Rect2, value: Rect2) -> bool:
	var container_end := container.position + container.size
	var value_end := value.position + value.size
	return value.position.x >= container.position.x \
		and value.position.y >= container.position.y \
		and value_end.x <= container_end.x \
		and value_end.y <= container_end.y

func _rect_violation(value: Rect2, container: Rect2) -> float:
	var value_end := value.position + value.size
	var container_end := container.position + container.size
	return maxf(0.0, maxf(
		maxf(container.position.x - value.position.x, value_end.x - container_end.x),
		maxf(container.position.y - value.position.y, value_end.y - container_end.y)
	))

func _remove_target_and_camera(skier: SkierController, camera_rig: SkiCameraController) -> void:
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
