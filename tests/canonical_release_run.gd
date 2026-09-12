extends Node

## Canonical deterministic release run (trace version canonical_release_run/v1).
##
## Fixed spawn plus a fixed scripted timeline: acceleration, linked carves,
## small/medium/large hero airs with clean landings, the longest runout, and at
## least five seconds of continued skiing after the final landing. Per-frame
## telemetry feeds the release performance characterization; named events make
## before/after comparisons explicit. Every station is derived from the
## authored course data, so the trace stays comparable across course revisions.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const ProfileMetrics := preload("res://tests/performance_profile_metrics.gd")
const TRACE_VERSION := "canonical_release_run/v1"
const HERO_JUMPS: Array[String] = ["SmallTable", "MediumTable", "LargeTable"]
const CONTINUE_AFTER_LANDING := [90, 120, 300]
const POP_HOLD_FRAMES := [6, 9, 12]
const POP_TRIGGER_LEAD_M := 1.5
const WARMUP_FRAMES := 25
const MAX_JUMP_FRAMES := 300
const MINIMUM_SAMPLES := 900

@onready var resort: Node = $Resort

var skier: SkierController
var camera: SkiCameraController
var course_profile: ParkCourseProfile
var failures: Array[String] = []
var events: Array[Dictionary] = []
var frame_index := 0
var wall_ms_samples: Array[float] = []
var physics_ms_samples: Array[float] = []
var process_ms_samples: Array[float] = []
var maximum_grounded_invalid_streak := 0
var grounded_invalid_frames := 0
var maximum_camera_distance := 0.0
var minimum_camera_distance := INF
var total_fallbacks := 0
var finish_frame := -1
var landing_frames: Dictionary = {}
var takeoff_frames: Dictionary = {}
var _finish_started := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	skier = resort.get_node("Skier") as SkierController
	camera = resort.get_node("CameraRig") as SkiCameraController
	course_profile = resort.get("course_profile") as ParkCourseProfile
	if skier == null or camera == null or course_profile == null:
		failures.append("Canonical run could not bind the skier, camera, or course profile")
		_finish()
		return
	await _run_trace()
	_validate_trace()
	_finish()

func _run_trace() -> void:
	_begin_segment("DROP_IN")
	_mark("DROP_IN")
	await _run_frames(60)
	await _steer("steer_right", 90.0, 90, "CARVE_R_1")
	await _steer("steer_left", 90.0, 90, "CARVE_L_1")
	await _steer("steer_right", 90.0, 90, "CARVE_R_2")
	Input.action_release("steer_right")
	Input.action_release("steer_left")
	for jump_index: int in range(HERO_JUMPS.size()):
		await _run_hero_jump(HERO_JUMPS[jump_index], jump_index + 1)
	await _run_to_finish()
	await _run_frames(90)
	_mark("POST_FINISH")

func _run_hero_jump(jump_name: String, jump_number: int) -> void:
	var spec := _spec_for(jump_name)
	if spec.is_empty():
		failures.append("Canonical run could not find the %s course spec" % jump_name)
		return
	_begin_segment("JUMP_%d_%s" % [jump_number, jump_name])
	var physics_profile := resort.get("physics_profile") as SkiPhysicsProfile
	var pop_strength := float(spec.get("pop", physics_profile.minimum_pop_strength))
	var sizing := ParkLayout.jump_table(
		physics_profile,
		float(spec.speed),
		float(spec.lip),
		float(spec.get("drop", 0.0)),
		pop_strength
	)
	var lip_edge_z := float(spec.z) - float(sizing.lip_length) * cos(deg_to_rad(ParkLayout.PITCH_DEG))
	# Scripted design trajectory: launch from the authored lip edge with the
	# same lip/pop velocity the course builder used to size the table and
	# landing. This keeps the three hero airs deterministic and comparable
	# across course revisions while the surrounding trace remains real input.
	var launch_origin := ParkLayout.snow_at(float(spec.x), lip_edge_z) + ParkLayout.snow_normal() * (float(sizing.lip_rise) + 0.05)
	var launch_velocity := (sizing.lip_dir as Vector3) * float(spec.speed) + ParkLayout.snow_normal() * physics_profile.pop_impulse * clampf(pop_strength, 0.0, 1.0)
	skier.reset_for_benchmark(Transform3D(ParkLayout.downhill_basis(), launch_origin), launch_velocity)
	camera.reset_immediate()
	var takeoff_frame := frame_index
	takeoff_frames[jump_name] = takeoff_frame
	_mark("TAKEOFF_%d" % jump_number)
	var landing_frame := -1
	for _frame: int in range(MAX_JUMP_FRAMES):
		await _run_frame()
		if skier.state == SkierController.State.GROUND:
			landing_frame = frame_index
			landing_frames[jump_name] = landing_frame
			_mark("LAND_%d" % jump_number)
			break
	if landing_frame < 0:
		failures.append("%s never landed cleanly" % jump_name)
	var continue_frames: int = CONTINUE_AFTER_LANDING[clampi(jump_number - 1, 0, CONTINUE_AFTER_LANDING.size() - 1)]
	await _run_frames(continue_frames)
	_mark("POST_LAND_%d" % jump_number)

func _run_to_finish() -> void:
	_begin_segment("FINISH")
	for _frame: int in range(420):
		await _run_frame()
		if skier.scoring.finished and finish_frame < 0:
			finish_frame = frame_index
			_mark("FINISH")
			return

func _steer(action: String, strength: float, frames: int, marker: String) -> void:
	Input.action_press(action, strength)
	await _run_frames(frames)
	Input.action_release(action)
	_mark(marker)

func _run_frames(count: int) -> void:
	for _frame: int in range(count):
		await _run_frame()

func _run_frame() -> void:
	var start_usec := Time.get_ticks_usec()
	await get_tree().physics_frame
	frame_index += 1
	var wall_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	wall_ms_samples.append(wall_ms)
	physics_ms_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	process_ms_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var snapshot := camera.debug_snapshot()
	var distance := float(snapshot.get("target_distance", 0.0))
	if distance > 1.0:
		maximum_camera_distance = maxf(maximum_camera_distance, distance)
		minimum_camera_distance = minf(minimum_camera_distance, distance)
	var grounded := skier.state == SkierController.State.GROUND or skier.state == SkierController.State.GRIND
	var recovery_active := bool(snapshot.get("composition_recovery_active", false))
	if grounded and not recovery_active and not bool(snapshot.get("composition_valid", true)):
		grounded_invalid_frames += 1
		_streak += 1
		maximum_grounded_invalid_streak = maxi(maximum_grounded_invalid_streak, _streak)
	else:
		_streak = 0
	var fallback_count := int(snapshot.get("camera_fallback_count", 0))
	if fallback_count > total_fallbacks:
		total_fallbacks = fallback_count
	if skier.scoring.finished and finish_frame < 0:
		finish_frame = frame_index
		_mark("FINISH")

var _streak := 0
var _segment := ""
var segment_fallbacks: Dictionary = {}

func _begin_segment(name: String) -> void:
	_segment = name
	segment_fallbacks[name] = total_fallbacks
	print("CANONICAL_SEGMENT name=%s frame=%d" % [name, frame_index])

func _mark(event: String) -> void:
	events.append({"name": event, "frame": frame_index, "z": skier.global_position.z if skier != null else 0.0, "fallbacks": total_fallbacks})
	print("CANONICAL_EVENT name=%s frame=%d z=%.1f fallbacks=%d state=%d" % [event, frame_index, events[-1].z, total_fallbacks, skier.state if skier != null else -1])

func _spec_for(name: String) -> Dictionary:
	for spec: Dictionary in course_profile.feature_specs():
		if str(spec.get("name", "")) == name:
			return spec
	return {}

func _validate_trace() -> void:
	var present: Dictionary = {}
	for event: Dictionary in events:
		present[str(event.name)] = true
	for required: String in ["DROP_IN", "CARVE_R_1", "CARVE_L_1", "CARVE_R_2", "TAKEOFF_1", "LAND_1", "TAKEOFF_2", "LAND_2", "TAKEOFF_3", "LAND_3", "FINISH"]:
		if not present.has(required):
			failures.append("Canonical trace never produced the %s event" % required)
	var airtimes: Array[float] = []
	for jump_name: String in HERO_JUMPS:
		if takeoff_frames.has(jump_name) and landing_frames.has(jump_name):
			airtimes.append(float(int(landing_frames[jump_name]) - int(takeoff_frames[jump_name])) / 60.0)
	if airtimes.size() == 3 and not (airtimes[0] < airtimes[1] and airtimes[1] < airtimes[2]):
		failures.append("Hero airtimes were not increasing: %s" % str(airtimes))
	if frame_index < MINIMUM_SAMPLES:
		failures.append("Canonical run only produced %d frames (expected %d)" % [frame_index, MINIMUM_SAMPLES])
	if maximum_grounded_invalid_streak > 15:
		failures.append("Canonical run held a grounded hard-composition streak of %d frames" % maximum_grounded_invalid_streak)
	if grounded_invalid_frames > 0:
		failures.append("Canonical run produced %d grounded hard-composition-invalid frames" % grounded_invalid_frames)
	if maximum_camera_distance > 7.42 or minimum_camera_distance < 3.33:
		failures.append("Canonical camera distance escaped its band: (%.2f, %.2f)" % [minimum_camera_distance, maximum_camera_distance])
	if total_fallbacks > 120:
		failures.append("Canonical run needed %d camera fallbacks" % total_fallbacks)
	var frames_after_final_landing := frame_index - int(landing_frames.get("LargeTable", frame_index))
	if frames_after_final_landing < 300:
		failures.append("Only %d frames followed the final landing (need 300)" % frames_after_final_landing)
	var summary := ProfileMetrics.summarize_frame_times(wall_ms_samples)
	var physics_summary := ProfileMetrics.summarize_frame_times(physics_ms_samples)
	var process_summary := ProfileMetrics.summarize_frame_times(process_ms_samples)
	var resort_metrics := {
		"objects": 0,
		"primitives": 0,
		"draw_calls": 0,
		"video_memory_bytes": 0,
		"texture_memory_bytes": 0,
		"buffer_memory_bytes": 0,
	}
	var profile := ProfileMetrics.make_profile(
		"daytime",
		"configured",
		TRACE_VERSION,
		"unknown",
		true,
		wall_ms_samples,
		resort_metrics,
		AudioManager.profiling_snapshot()
	)
	(profile["frames"] as Dictionary)["physics_p50_ms"] = physics_summary.get("p50_ms", 0.0)
	(profile["frames"] as Dictionary)["physics_p95_ms"] = physics_summary.get("p95_ms", 0.0)
	(profile["frames"] as Dictionary)["process_p95_ms"] = process_summary.get("p95_ms", 0.0)
	var probe_summary: Dictionary = {}
	if resort.has_method("player_probe_summary"):
		probe_summary = resort.call("player_probe_summary") as Dictionary
	profile["probe"] = probe_summary
	profile["events"] = events
	var validation := ProfileMetrics.validate_profile(profile)
	if not bool(validation.get("valid", false)):
		failures.append("Canonical performance profile failed schema validation: %s" % str(validation.get("errors", [])))
	var profile_path := "user://canonical_release_profile.json"
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		failures.append("Could not write the canonical release profile")
	else:
		file.store_string(JSON.stringify(profile, "\t"))
		file.close()
	print("CANONICAL_SUMMARY trace=%s frames=%d wall_avg_ms=%.2f wall_p50_ms=%.2f wall_p95_ms=%.2f wall_p99_ms=%.2f physics_p95_ms=%.2f process_p95_ms=%.2f camera=(%.2f,%.2f) fallbacks=%d seg_fallbacks=%s grounded_invalid=%d max_streak=%d airtimes=%s finish_frame=%d probe=%s profile=%s" % [
		TRACE_VERSION,
		frame_index,
		float(summary.get("average_ms", 0.0)),
		float(summary.get("p50_ms", 0.0)),
		float(summary.get("p95_ms", 0.0)),
		float(summary.get("p99_ms", 0.0)),
		float(physics_summary.get("p95_ms", 0.0)),
		float(process_summary.get("p95_ms", 0.0)),
		minimum_camera_distance,
		maximum_camera_distance,
		total_fallbacks,
		str(segment_fallbacks),
		grounded_invalid_frames,
		maximum_grounded_invalid_streak,
		str(airtimes),
		finish_frame,
		JSON.stringify(probe_summary),
		ProjectSettings.globalize_path(profile_path),
	])

func _finish() -> void:
	if _finish_started:
		return
	_finish_started = true
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CANONICAL_RELEASE_PASS: deterministic trace, hero progression, camera band, and performance profile validated")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CANONICAL_RELEASE_FAIL: " + failure)
	get_tree().quit(1)
