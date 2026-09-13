extends Node

## Uninterrupted production-course release trace. Unlike the deterministic
## canonical benchmark, this fixture never relocates the skier or camera. It
## starts at the real spawn, drives only Input actions, uses the authored snow
## and feature collisions, lands every hero table, keeps riding, and crosses
## the real finish trigger.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const VisualEvidence := preload("res://tests/visual_evidence.gd")
const TRACE_VERSION := "continuous_course_release/v1"
const HERO_JUMPS: Array[String] = ["SmallTable", "MediumTable", "LargeTable"]
const MAX_TRACE_SECONDS := 55.0
const MIN_STABLE_GROUND_SECONDS := 0.5
const MIN_POST_LARGE_SECONDS := 5.0
const MIN_DROP_IN_SLOPE_M := 60.0
const MAX_DROP_IN_SLOPE_M := 100.0
const ACCEPTANCE_PHYSICS_HZ := 60

@onready var resort: Node = $Resort

var skier: SkierController
var camera: SkiCameraController
var course_profile: ParkCourseProfile
var physics_profile: SkiPhysicsProfile
var jump_specs: Array[Dictionary] = []
var jump_records: Array[Dictionary] = []
var events: Array[Dictionary] = []
var failures: Array[String] = []
var frame_index := 0
var physics_hz := 60.0
var next_jump_index := 0
var active_jump_index := -1
var previous_state := SkierController.State.AIR
var jump_charging := false
var jump_released := false
var linked_left_seen := false
var linked_right_seen := false
var maximum_camera_distance := 0.0
var minimum_camera_distance := INF
var hard_composition_invalid_frames := 0
var camera_fallback_count := 0
var finish_frame := -1
var post_large_landing_frame := -1
var bail_seen := false
var _finish_started := false
var capture_continuous := false
var evidence_root := "res://.godot_user/visual_runs/continuous_course_release"
var evidence: VisualEvidenceSession
var pending_evidence_captures := 0
var captured_apexes: Dictionary = {}
var left_carve_capture_requested := false
var right_carve_capture_requested := false
var post_large_capture_requested := false
var previous_normal_velocity := 0.0

func _enter_tree() -> void:
	# The release fixture's primary acceptance rate is 60 Hz. All decisions are
	# distance/state based so this remains tolerant of minor timing differences;
	# the existing dedicated suites retain their 30/60/120 Hz sweeps.
	Engine.physics_ticks_per_second = ACCEPTANCE_PHYSICS_HZ

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_hz = maxf(float(Engine.physics_ticks_per_second), 1.0)
	skier = resort.get_node_or_null("Skier") as SkierController
	camera = resort.get_node_or_null("CameraRig") as SkiCameraController
	course_profile = resort.get("course_profile") as ParkCourseProfile
	physics_profile = resort.get("physics_profile") as SkiPhysicsProfile
	if skier == null or camera == null or course_profile == null or physics_profile == null:
		failures.append("Could not bind the production skier, camera, or profiles")
		_finish()
		return
	_configure_optional_evidence()
	_build_course_trace()
	skier.feature_used.connect(_on_feature_used)
	skier.landed.connect(_on_landed)
	previous_state = skier.state
	_mark("SPAWN")
	await _run_trace()
	_validate_trace()
	_write_profile()
	if capture_continuous:
		await _wait_for_evidence_captures()
	_finish()

func _configure_optional_evidence() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture-continuous":
			capture_continuous = true
		elif argument.begins_with("--evidence-root="):
			var requested := argument.trim_prefix("--evidence-root=")
			if requested.begins_with("res://.godot_user/"):
				evidence_root = requested
	if not capture_continuous:
		return
	if RuntimeEnvironment.is_headless():
		failures.append("Continuous visual evidence requires a GPU renderer")
		return
	var ui := resort.get_node_or_null("GameUI") as CanvasItem
	if ui != null:
		ui.visible = false
	evidence = VisualEvidence.begin({
		"suite_id": "continuous_course_release",
		"evidence_root": evidence_root,
		"fixed_fps": ACCEPTANCE_PHYSICS_HZ,
		"capture_width": 1280,
		"capture_height": 720,
		"context": {
			"scene": "continuous_course_release_acceptance",
			"commit_sha": _head_sha(),
			"working_tree_dirty": _working_tree_dirty(),
			"environment": "daytime",
			"preset": int(GameSettings.active.get("graphics_preset", -1)),
			"render_scale": get_viewport().scaling_3d_scale,
			"renderer": "Forward Plus",
			"capture_mode": "uninterrupted_spawn_to_finish",
			"trace_version": TRACE_VERSION,
		},
	})

func _build_course_trace() -> void:
	var specs_by_name: Dictionary = {}
	for spec: Dictionary in course_profile.feature_specs():
		specs_by_name[str(spec.get("name", ""))] = spec
	for name: String in HERO_JUMPS:
		var spec := specs_by_name.get(name, {}) as Dictionary
		if spec.is_empty():
			failures.append("Course profile is missing %s" % name)
			continue
		var sizing := ParkLayout.jump_table(
			physics_profile,
			float(spec.get("speed", 0.0)),
			float(spec.get("lip", 0.0)),
			float(spec.get("drop", 0.0)),
			float(spec.get("pop", physics_profile.minimum_pop_strength))
		)
		var cos_pitch := cos(deg_to_rad(ParkLayout.PITCH_DEG))
		var lip_length := float(sizing.get("lip_length", 0.0))
		var landing_length := float(sizing.get("landing_length", 0.0))
		var run_in := clampf(lip_length * 0.68, 4.5, 7.5)
		var run_out := clampf(landing_length * 0.28, 3.5, 6.0)
		var structure_length := lip_length + float(sizing.get("table_length", 0.0)) + ParkLayout.TABLE_LANDING_SEAM_M + landing_length + run_out
		var geometry := {
			"run_in_z": float(spec.z) + run_in * cos_pitch,
			"lip_edge_z": float(spec.z) - lip_length * cos_pitch,
			"end_z": float(spec.z) - structure_length * cos_pitch,
		}
		jump_specs.append({"spec": spec, "sizing": sizing, "geometry": geometry})
		jump_records.append({
			"name": name,
			"feature_id": StringName(spec.get("feature_id", &"")),
			"feature_takeoff": false,
			"takeoff_frame": -1,
			"landing_frame": -1,
			"lip_speed_mps": -1.0,
			"takeoff_position_m": Vector3.ZERO,
			"landing_position_m": Vector3.ZERO,
			"airtime_seconds": -1.0,
			"lateral_line_error_m": INF,
			"landing_result": {},
			"stable_recovery_seconds": -1.0,
			"continuous_grounded_seconds": 0.0,
			"current_grounded_frames": 0,
			"maximum_grounded_frames": 0,
		})

func _run_trace() -> void:
	var maximum_frames := int(ceil(MAX_TRACE_SECONDS * physics_hz))
	while frame_index < maximum_frames:
		_apply_controls()
		await get_tree().physics_frame
		frame_index += 1
		_sample_frame()
		if frame_index % int(physics_hz * 2.0) == 0:
			print("CONTINUOUS_RELEASE_PROGRESS frame=%d jump=%d state=%d position=%s speed=%.2f respawns=%d" % [frame_index, next_jump_index + 1, skier.state, str(skier.global_position), skier.velocity.length(), skier.respawn_count])
		if skier.state == SkierController.State.BAIL:
			bail_seen = true
			failures.append("Skier bailed at frame %d, position %s" % [frame_index, str(skier.global_position)])
			break
		if skier.scoring.finished:
			finish_frame = frame_index
			_mark("FINISH")
			break
	_cleanup_input()

func _apply_controls() -> void:
	_clear_continuous_input()
	if skier == null or skier.state == SkierController.State.BAIL:
		return
	var target_x := 0.0 if next_jump_index >= HERO_JUMPS.size() else float((jump_specs[next_jump_index].spec as Dictionary).x)
	var steer_action := ""
	var steer_strength := 0.0
	# Two distance-based arcs prove linked left/right steering without relying
	# on a particular frame count. The remainder uses a damped world-line
	# controller so small physics-rate differences cannot miss a ramp.
	if next_jump_index == 0 and not jump_charging:
		var small_geometry := jump_specs[0].geometry as Dictionary
		var drop_span := course_profile.spawn_world_z() - float(small_geometry.run_in_z)
		var left_end := course_profile.spawn_world_z() - drop_span * 0.28
		var right_end := course_profile.spawn_world_z() - drop_span * 0.44
		if skier.global_position.z > left_end:
			steer_action = "steer_left"
			steer_strength = 0.52
			linked_left_seen = true
			if capture_continuous and not left_carve_capture_requested and skier.velocity.length() > 5.0:
				left_carve_capture_requested = true
				_schedule_evidence_capture("CARVE_LEFT")
		elif skier.global_position.z > right_end:
			steer_action = "steer_right"
			steer_strength = 0.34
			linked_right_seen = true
			if capture_continuous and not right_carve_capture_requested:
				right_carve_capture_requested = true
				_schedule_evidence_capture("CARVE_RIGHT")
	if steer_action.is_empty():
		var predicted_x := skier.global_position.x + skier.velocity.x * 0.55
		var line_error := predicted_x - target_x
		if absf(line_error) > 0.22:
			steer_action = "steer_left" if line_error > 0.0 else "steer_right"
			steer_strength = clampf(absf(line_error) / 9.0, 0.18, 0.58)
	if not steer_action.is_empty() and skier.state == SkierController.State.GROUND:
		Input.action_press(steer_action, steer_strength)

	if next_jump_index < HERO_JUMPS.size():
		var entry := jump_specs[next_jump_index]
		var spec := entry.spec as Dictionary
		var geometry := entry.geometry as Dictionary
		var target_speed := float(spec.speed)
		var distance_to_lip := skier.global_position.z - float(geometry.lip_edge_z)
		if skier.velocity.length() > target_speed + 1.0 and distance_to_lip < 28.0 and distance_to_lip > 1.5:
			Input.action_press("brake", clampf((skier.velocity.length() - target_speed) / 7.0, 0.18, 0.72))
		if not jump_charging and not jump_released and skier.global_position.z <= float(spec.z) + 1.5 and skier.global_position.z > float(geometry.lip_edge_z):
			jump_charging = true
			Input.action_press("jump", 1.0)
			_mark("CHARGE_%d" % (next_jump_index + 1))
		elif jump_charging:
			if skier.global_position.z <= float(geometry.lip_edge_z) + 1.0 or skier.state != SkierController.State.GROUND:
				Input.action_release("jump")
				jump_charging = false
				jump_released = true
				_mark("RELEASE_%d" % (next_jump_index + 1))
			else:
				Input.action_press("jump", 1.0)
	else:
		var seconds_after_large := _seconds_after_large_landing()
		# Make the required five seconds real skiing time without moving the
		# finish: controlled braking early in the runout, then release and cross.
		if seconds_after_large < 4.0 or (seconds_after_large < MIN_POST_LARGE_SECONDS and skier.global_position.z < course_profile.finish_trigger_world_z() + 28.0):
			Input.action_press("brake", 0.85)

func _sample_frame() -> void:
	var snapshot := camera.debug_snapshot()
	var distance := float(snapshot.get("target_distance", 0.0))
	if distance > 0.0:
		minimum_camera_distance = minf(minimum_camera_distance, distance)
		maximum_camera_distance = maxf(maximum_camera_distance, distance)
	# The rig is allowed one initialization window before the first normal
	# gameplay sample; no post-warmup hard-invalid frame is accepted.
	if frame_index > int(ceil(0.5 * physics_hz)) and not bool(snapshot.get("composition_valid", true)) and not bool(snapshot.get("composition_recovery_active", false)):
		hard_composition_invalid_frames += 1
	camera_fallback_count = maxi(camera_fallback_count, int(snapshot.get("camera_fallback_count", 0)))
	var normal_velocity := skier.velocity.dot(ParkLayout.snow_normal())
	if active_jump_index >= 0 and previous_normal_velocity > 0.0 and normal_velocity <= 0.0 and not captured_apexes.has(active_jump_index):
		captured_apexes[active_jump_index] = true
		_schedule_evidence_capture("APEX_%d" % (active_jump_index + 1))
	previous_normal_velocity = normal_velocity
	if capture_continuous and post_large_landing_frame >= 0 and not post_large_capture_requested and _seconds_after_large_landing() >= MIN_POST_LARGE_SECONDS:
		post_large_capture_requested = true
		_schedule_evidence_capture("POST_LARGE_5S")

	if active_jump_index < 0 and next_jump_index > 0:
		var recovery := jump_records[next_jump_index - 1]
		if skier.state == SkierController.State.GROUND and skier.contact.grounded:
			recovery.current_grounded_frames = int(recovery.current_grounded_frames) + 1
			recovery.maximum_grounded_frames = maxi(int(recovery.maximum_grounded_frames), int(recovery.current_grounded_frames))
			if float(recovery.stable_recovery_seconds) < 0.0 and int(recovery.current_grounded_frames) >= int(ceil(MIN_STABLE_GROUND_SECONDS * physics_hz)):
				recovery.stable_recovery_seconds = float(recovery.current_grounded_frames) / physics_hz
		else:
			recovery.current_grounded_frames = 0

	if previous_state != SkierController.State.AIR and skier.state == SkierController.State.AIR and next_jump_index < HERO_JUMPS.size():
		var entry := jump_specs[next_jump_index]
		var geometry := entry.geometry as Dictionary
		var spec := entry.spec as Dictionary
		if skier.global_position.z <= float(spec.z) + 3.0 and skier.global_position.z >= float(geometry.lip_edge_z) - 4.0:
			active_jump_index = next_jump_index
			var record := jump_records[active_jump_index]
			record.takeoff_frame = frame_index
			record.lip_speed_mps = skier.velocity.length()
			record.takeoff_position_m = skier.global_position
			record.lateral_line_error_m = absf(skier.global_position.x - float(spec.x))
			if active_jump_index > 0:
				var prior := jump_records[active_jump_index - 1]
				prior.continuous_grounded_seconds = float(prior.maximum_grounded_frames) / physics_hz
			_mark("TAKEOFF_%d" % (active_jump_index + 1))
			previous_normal_velocity = skier.velocity.dot(ParkLayout.snow_normal())
	previous_state = skier.state

func _on_feature_used(feature_id: StringName, _feature_kind: StringName, use_kind: StringName) -> void:
	if use_kind != &"takeoff":
		return
	for record: Dictionary in jump_records:
		if StringName(record.feature_id) == feature_id:
			record.feature_takeoff = true
			return

func _on_landed(result: Dictionary) -> void:
	if active_jump_index < 0 or active_jump_index >= jump_records.size():
		return
	var record := jump_records[active_jump_index]
	record.landing_frame = frame_index + 1
	record.landing_position_m = skier.global_position
	record.airtime_seconds = float(int(record.landing_frame) - int(record.takeoff_frame)) / physics_hz
	record.landing_result = result.duplicate(true)
	_mark("LAND_%d" % (active_jump_index + 1))
	if active_jump_index == HERO_JUMPS.size() - 1:
		post_large_landing_frame = int(record.landing_frame)
	next_jump_index = active_jump_index + 1
	active_jump_index = -1
	jump_charging = false
	jump_released = false

func _validate_trace() -> void:
	if not jump_records.is_empty():
		var final_record := jump_records[-1]
		final_record.continuous_grounded_seconds = float(final_record.maximum_grounded_frames) / physics_hz
	if not linked_left_seen or not linked_right_seen:
		failures.append("Drop-in did not exercise linked left/right steering")
	if jump_specs.size() == HERO_JUMPS.size():
		var small_geometry := jump_specs[0].geometry as Dictionary
		var drop_in := (course_profile.spawn_world_z() - float(small_geometry.run_in_z)) / cos(deg_to_rad(ParkLayout.PITCH_DEG))
		if drop_in < MIN_DROP_IN_SLOPE_M or drop_in > MAX_DROP_IN_SLOPE_M:
			failures.append("Measured drop-in %.1f slope m escaped %.0f-%.0f m" % [drop_in, MIN_DROP_IN_SLOPE_M, MAX_DROP_IN_SLOPE_M])
	for index: int in range(jump_records.size()):
		var record := jump_records[index]
		var spec := jump_specs[index].spec as Dictionary
		if int(record.takeoff_frame) < 0:
			failures.append("%s never produced a real takeoff" % record.name)
			continue
		if not bool(record.feature_takeoff):
			failures.append("%s did not emit its authoritative feature takeoff" % record.name)
		if int(record.landing_frame) < 0:
			failures.append("%s never produced a real landing" % record.name)
		if float(record.lateral_line_error_m) > float(spec.width) * 0.5:
			failures.append("%s takeoff line error %.2f m exceeded half-width %.2f m" % [record.name, record.lateral_line_error_m, float(spec.width) * 0.5])
		if float(record.lip_speed_mps) < float(spec.speed) * 0.72 or float(record.lip_speed_mps) > float(spec.speed) * 1.35:
			failures.append("%s lip speed %.2f m/s escaped its tolerant design band" % [record.name, record.lip_speed_mps])
		if float(record.airtime_seconds) < 0.2 or float(record.airtime_seconds) > 4.5:
			failures.append("%s airtime %.2f s escaped the physical jump window" % [record.name, record.airtime_seconds])
		if float(record.stable_recovery_seconds) < 0.0:
			failures.append("%s never established %.1f s of stable grounded recovery" % [record.name, MIN_STABLE_GROUND_SECONDS])
	if not skier.scoring.finished or finish_frame < 0:
		failures.append("The skier did not cross the actual finish trigger")
	if post_large_landing_frame < 0 or finish_frame - post_large_landing_frame < int(ceil(MIN_POST_LARGE_SECONDS * physics_hz)):
		failures.append("Finish occurred before %.1f s of post-LargeTable skiing" % MIN_POST_LARGE_SECONDS)
	if skier.respawn_count != 0:
		failures.append("Continuous trace respawned %d times" % skier.respawn_count)
	if bail_seen:
		failures.append("Continuous trace included a bail")
	if hard_composition_invalid_frames > 0:
		failures.append("Camera produced %d hard-composition-invalid frames" % hard_composition_invalid_frames)
	if minimum_camera_distance < camera.minimum_camera_distance - 0.05 or maximum_camera_distance > camera.maximum_camera_distance + 0.05:
		failures.append("Camera distance escaped safety band: %.2f-%.2f m" % [minimum_camera_distance, maximum_camera_distance])

func _write_profile() -> void:
	if jump_specs.is_empty():
		return
	var small_geometry := jump_specs[0].geometry as Dictionary
	var serializable_jumps: Array[Dictionary] = []
	for record: Dictionary in jump_records:
		var copy := record.duplicate(true)
		copy.erase("current_grounded_frames")
		copy.erase("maximum_grounded_frames")
		copy["takeoff_position_m"] = _vector3_array(record.takeoff_position_m as Vector3)
		copy["landing_position_m"] = _vector3_array(record.landing_position_m as Vector3)
		serializable_jumps.append(copy)
	var payload := {
		"trace_version": TRACE_VERSION,
		"head_sha": _head_sha(),
		"physics_hz": physics_hz,
		"frames": frame_index,
		"duration_seconds": float(frame_index) / physics_hz,
		"spawn_world_z": course_profile.spawn_world_z(),
		"small_table_structure_start_z": float(small_geometry.run_in_z),
		"drop_in_slope_m": (course_profile.spawn_world_z() - float(small_geometry.run_in_z)) / cos(deg_to_rad(ParkLayout.PITCH_DEG)),
		"elapsed_to_first_takeoff_seconds": float(int(jump_records[0].takeoff_frame)) / physics_hz,
		"jumps": serializable_jumps,
		"events": events,
		"camera": {
			"minimum_target_distance_m": minimum_camera_distance,
			"maximum_target_distance_m": maximum_camera_distance,
			"hard_composition_invalid_frames": hard_composition_invalid_frames,
			"fallback_count": camera_fallback_count,
		},
		"finish": {
			"finished": skier.scoring.finished,
			"frame": finish_frame,
			"post_large_seconds": _seconds_after_large_landing(),
		},
		"respawn_count": skier.respawn_count,
		"failures": failures,
	}
	var path := "user://continuous_course_release_profile.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("Could not write continuous release telemetry")
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	if evidence != null:
		var scenario_id := "continuous_course.telemetry"
		evidence.register_scenario(scenario_id, {"capture_kind": "structured_trace"})
		if evidence.write_json_artifact(scenario_id, "telemetry", "continuous_course_release_profile.json", payload, {"trace_version": TRACE_VERSION}).is_empty():
			failures.append("Could not write continuous visual-evidence telemetry")
	print("CONTINUOUS_RELEASE_SUMMARY profile=%s data=%s" % [ProjectSettings.globalize_path(path), JSON.stringify(payload)])

func _mark(event_name: String) -> void:
	var event := {
		"name": event_name,
		"frame": frame_index,
		"time_seconds": float(frame_index) / physics_hz,
		"position_m": _vector3_array(skier.global_position) if skier != null else [0.0, 0.0, 0.0],
		"speed_mps": skier.velocity.length() if skier != null else 0.0,
	}
	events.append(event)
	print("CONTINUOUS_RELEASE_EVENT name=%s frame=%d position=%s speed=%.2f" % [event_name, frame_index, str(event.position_m), float(event.speed_mps)])
	if capture_continuous and (event_name.begins_with("CHARGE_") or event_name.begins_with("TAKEOFF_") or event_name.begins_with("LAND_") or event_name == "FINISH"):
		_schedule_evidence_capture(event_name)

func _schedule_evidence_capture(event_name: String) -> void:
	if evidence == null or RuntimeEnvironment.is_headless():
		return
	pending_evidence_captures += 1
	call_deferred("_capture_evidence_frame", event_name, frame_index)

func _capture_evidence_frame(event_name: String, event_frame: int) -> void:
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(true)
	var image := get_viewport().get_texture().get_image() if get_viewport().get_texture() != null else null
	var scenario_id := "continuous_course.%s" % event_name.to_lower()
	var metadata := {
		"artifact_filename": "%04d_%s.png" % [event_frame, event_name.to_lower()],
		"event": event_name,
		"frame_index": event_frame,
		"time_s": float(event_frame) / physics_hz,
		"capture_kind": "uninterrupted_gameplay_event",
		"view": "gameplay",
		"position_m": _vector3_array(skier.global_position) if skier != null else [0.0, 0.0, 0.0],
		"state": skier.state if skier != null else -1,
	}
	if image == null or image.is_empty() or evidence.capture_image(scenario_id, "raw", image, metadata).is_empty():
		failures.append("Could not capture continuous evidence frame %s" % event_name)
	else:
		evidence.record_sample(scenario_id, metadata)
	pending_evidence_captures = maxi(pending_evidence_captures - 1, 0)

func _wait_for_evidence_captures() -> void:
	var deadline_frames := frame_index + int(physics_hz * 3.0)
	while pending_evidence_captures > 0 and frame_index < deadline_frames:
		await get_tree().process_frame
		frame_index += 1
	if pending_evidence_captures > 0:
		failures.append("Timed out waiting for %d continuous evidence captures" % pending_evidence_captures)

func _seconds_after_large_landing() -> float:
	if post_large_landing_frame < 0:
		return 0.0
	return float(frame_index - post_large_landing_frame) / physics_hz

func _cleanup_input() -> void:
	for action: StringName in [&"steer_left", &"steer_right", &"brake", &"jump", &"tuck"]:
		Input.action_release(action)

func _clear_continuous_input() -> void:
	for action: StringName in [&"steer_left", &"steer_right", &"brake", &"tuck"]:
		Input.action_release(action)

func _head_sha() -> String:
	var output: Array = []
	var exit_code := OS.execute("git", PackedStringArray(["rev-parse", "HEAD"]), output, true)
	return str(output[0]).strip_edges() if exit_code == 0 and not output.is_empty() else "unknown"

func _working_tree_dirty() -> bool:
	var output: Array = []
	var exit_code := OS.execute("git", PackedStringArray(["status", "--porcelain"]), output, true)
	return exit_code != 0 or (not output.is_empty() and not str(output[0]).strip_edges().is_empty())

func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _finish() -> void:
	if _finish_started:
		return
	_finish_started = true
	_cleanup_input()
	AudioManager.shutdown_audio()
	if evidence != null:
		evidence.finish(0 if failures.is_empty() else 1)
	if failures.is_empty():
		print("CONTINUOUS_COURSE_RELEASE_PASS: uninterrupted spawn-to-finish three-jump gameplay validated")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CONTINUOUS_COURSE_RELEASE_FAIL: " + failure)
	get_tree().quit(1)
