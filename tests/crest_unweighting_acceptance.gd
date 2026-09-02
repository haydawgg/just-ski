extends Node3D

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SnowMaterial := preload("res://world/snow_material.gd")

const START_SPEED := 8.0
const START_DISTANCE_UPHILL := 7.0
const CREST_WINDOW_BEFORE := 2.5
const RUNOUT_DISTANCE := 5.0
const RUNOUT_FULL_CONTACT_SECONDS := 0.20
const MAX_RUN_SECONDS := 5.0
const STEER_AMOUNT := 0.38
# These are signed probe-distance differences in metres. The thresholds are
# deliberately fixed before tuning so a candidate cannot redefine success.
const TIP_LOAD_EXCURSION_MIN := 0.30
const STRONG_TIP_LOAD_EXCURSION_MIN := 0.175
const VERTICAL_RESPONSE_MIN := 0.20
const RECONTACT_MAX_SECONDS := 0.75
const MIN_PROGRESS_SPEED := 1.0

const ROLLER_CASES: Array[Dictionary] = [
	{"name": "SummitRollerA", "z": 48.0, "length": 5.0, "height": 0.42, "width": 10.0, "strong": false},
	{"name": "SummitRollerB", "z": 25.0, "length": 5.5, "height": 0.50, "width": 10.0, "strong": false},
	{"name": "UpperRoller", "z": 0.0, "length": 8.0, "height": 0.80, "width": 9.0, "strong": true},
	{"name": "MidRoller", "z": -30.0, "length": 9.0, "height": 0.70, "width": 12.0, "strong": true},
]

var skier: SkierController
var run_queue: Array[Dictionary] = []
var run_index := -1
var current_run: Dictionary = {}
var current_metrics: Dictionary = {}
var current_trace: Array[Dictionary] = []
var suite_results: Array[Dictionary] = []
var run_clock := 0.0
var failures: Array[String] = []

func _ready() -> void:
	var requested_ticks := _requested_physics_ticks()
	if requested_ticks > 0:
		Engine.physics_ticks_per_second = requested_ticks
	process_physics_priority = 100
	_build_course()
	_build_skier()
	_build_run_queue()
	call_deferred("_start_next_run")

func _requested_physics_ticks() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--crest-physics-ticks="):
			continue
		var requested := int(argument.trim_prefix("--crest-physics-ticks="))
		if requested in [30, 60, 120]:
			return requested
	return 0

func _physics_process(delta: float) -> void:
	if current_run.is_empty():
		return
	run_clock += delta
	_sample_run()
	if run_clock > MAX_RUN_SECONDS:
		_fail_current_run("timed out before the runout")
		_start_next_run()
		return
	var distance_along := _distance_along_roller()
	var runout_end := float(current_run.length) + RUNOUT_DISTANCE
	if distance_along >= runout_end:
		_finish_current_run()
		_start_next_run()

func _build_course() -> void:
	ParkLayout.add_slope_box(
		self,
		"CrestBase",
		0.0,
		8.0,
		Vector3(34.0, 2.4, 150.0),
		0.0,
		Color("#e8f5fb"),
		SnowMaterial.Kind.PACKED,
		true
	)
	for roller: Dictionary in ROLLER_CASES:
		ParkLayout.add_roller(
			self,
			str(roller.name),
			0.0,
			float(roller.z),
			float(roller.length),
			float(roller.height),
			float(roller.width)
		)

func _build_skier() -> void:
	skier = SkierController.new()
	skier.name = "Skier"
	add_child(skier)

func _build_run_queue() -> void:
	for roller: Dictionary in ROLLER_CASES:
		for mode: String in ["STRAIGHT", "CARVE"]:
			var run := roller.duplicate()
			run["mode"] = mode
			run_queue.append(run)

func _start_next_run() -> void:
	_release_inputs()
	run_index += 1
	if run_index >= run_queue.size():
		_finish_suite()
		return
	current_run = run_queue[run_index]
	_reset_metrics()
	run_clock = 0.0
	var roller_start := ParkLayout.snow_at(0.0, float(current_run.z))
	var spawn := ParkLayout.snow_at(0.0, float(current_run.z) + START_DISTANCE_UPHILL) + ParkLayout.snow_normal() * 1.15
	var start_transform := Transform3D(ParkLayout.downhill_basis(), spawn)
	skier.reset_for_benchmark(start_transform, ParkLayout.downhill() * START_SPEED)
	if str(current_run.mode) == "CARVE":
		Input.action_press("steer_left", STEER_AMOUNT)
	print("CREST_START case=%s mode=%s roller_start=%s length=%.2f height=%.2f profile_z=%.2f" % [
		str(current_run.name),
		str(current_run.mode),
		roller_start,
		float(current_run.length),
		float(current_run.height),
		skier.profile.left_front_probe_offset.z,
	])

func _reset_metrics() -> void:
	current_trace = []
	current_metrics = {
		"started": false,
		"front_samples": 0,
		"rear_samples": 0,
		"sample_count": 0,
		"crest_samples": 0,
		"partial_contact_samples": 0,
		"front_load_samples": 0,
		"rear_load_samples": 0,
		"crest_tip_min": INF,
		"crest_tip_max": -INF,
		"tip_min": INF,
		"tip_max": -INF,
		"normal_velocity_min": INF,
		"normal_velocity_max": -INF,
		"world_vertical_min": INF,
		"world_vertical_max": -INF,
		"min_total_contacts": 4,
		"current_partial_frames": 0,
		"max_partial_frames": 0,
		"air_frames": 0,
		"max_speed": 0.0,
		"min_speed": INF,
		"runout_full_frames": 0,
		"crest_exit_clock": -1.0,
		"recontact_time": -1.0,
		"collision_count": 0,
		"speed_discontinuity": false,
		"non_finite": false,
		"last_distance": -INF,
	}

func _sample_run() -> void:
	var distance_along := _distance_along_roller()
	var window_end := float(current_run.length) + RUNOUT_DISTANCE
	if distance_along < -CREST_WINDOW_BEFORE or distance_along > window_end:
		return
	current_metrics.started = true
	current_metrics.sample_count += 1
	var front_hits := int(skier.contact.left_front_valid) + int(skier.contact.right_front_valid)
	var rear_hits := int(skier.contact.left_rear_valid) + int(skier.contact.right_rear_valid)
	var total_hits := front_hits + rear_hits
	current_metrics.front_samples += front_hits
	current_metrics.rear_samples += rear_hits
	current_metrics.min_total_contacts = mini(int(current_metrics.min_total_contacts), total_hits)
	if total_hits < 4:
		current_metrics.partial_contact_samples += 1
	var reference_normal := skier.contact.average_normal
	if reference_normal.length_squared() < 0.01:
		reference_normal = ParkLayout.snow_normal()
	var normal_velocity := skier.velocity.dot(reference_normal.normalized())
	var world_vertical := skier.velocity.y
	if is_finite(skier.contact.tip_load):
		current_metrics.tip_min = minf(float(current_metrics.tip_min), skier.contact.tip_load)
		current_metrics.tip_max = maxf(float(current_metrics.tip_max), skier.contact.tip_load)
		if distance_along >= 0.0 and distance_along <= float(current_run.length):
			current_metrics.crest_samples += 1
			current_metrics.crest_tip_min = minf(float(current_metrics.crest_tip_min), skier.contact.tip_load)
			current_metrics.crest_tip_max = maxf(float(current_metrics.crest_tip_max), skier.contact.tip_load)
			if distance_along <= float(current_run.length) * 0.45 and skier.contact.tip_load >= 0.02:
				current_metrics.front_load_samples += 1
			if distance_along >= float(current_run.length) * 0.55 and skier.contact.tip_load <= -0.02:
				current_metrics.rear_load_samples += 1
	else:
		current_metrics.non_finite = true
	if is_finite(normal_velocity):
		current_metrics.normal_velocity_min = minf(float(current_metrics.normal_velocity_min), normal_velocity)
		current_metrics.normal_velocity_max = maxf(float(current_metrics.normal_velocity_max), normal_velocity)
	else:
		current_metrics.non_finite = true
	if is_finite(world_vertical):
		current_metrics.world_vertical_min = minf(float(current_metrics.world_vertical_min), world_vertical)
		current_metrics.world_vertical_max = maxf(float(current_metrics.world_vertical_max), world_vertical)
	else:
		current_metrics.non_finite = true
	var speed := skier.velocity.length()
	if not is_finite(speed):
		current_metrics.non_finite = true
	else:
		current_metrics.max_speed = maxf(float(current_metrics.max_speed), speed)
		current_metrics.min_speed = minf(float(current_metrics.min_speed), speed)
	current_trace.append({
		"t": snappedf(run_clock, 0.001),
		"distance_along": snappedf(distance_along, 0.001),
		"front_hits": front_hits,
		"rear_hits": rear_hits,
		"front_fraction": snappedf(float(front_hits) / 2.0, 0.001),
		"rear_fraction": snappedf(float(rear_hits) / 2.0, 0.001),
		"tip_load": snappedf(skier.contact.tip_load, 0.001),
		"contact_confidence": snappedf(skier.contact.confidence, 0.001),
		"average_distance": snappedf(skier.contact.average_distance, 0.001),
		"normal_velocity": snappedf(normal_velocity, 0.001),
		"world_vertical_velocity": snappedf(world_vertical, 0.001),
		"along_track_speed": snappedf(skier.velocity.dot(ParkLayout.downhill()), 0.001),
		"steering_input": snappedf(skier.steering_input, 0.001),
		"available_grip": snappedf(skier.available_grip, 0.001),
		"lateral_slip": snappedf(skier.lateral_slip, 0.001),
		"state": SkierController.State.keys()[skier.state],
		"grounded": skier.contact.grounded,
		"airborne": skier.state == SkierController.State.AIR or not skier.contact.grounded,
		"collisions": skier.last_collision_colliders.duplicate(),
	})
	if skier.state == SkierController.State.AIR or not skier.contact.grounded:
		current_metrics.air_frames += 1
	var partial_support := skier.contact.grounded and (front_hits < 2 or rear_hits < 2) and speed > 1.0
	if partial_support:
		current_metrics.current_partial_frames += 1
		current_metrics.max_partial_frames = maxi(int(current_metrics.max_partial_frames), int(current_metrics.current_partial_frames))
	else:
		current_metrics.current_partial_frames = 0
	if distance_along >= float(current_run.length) + 1.0:
		if float(current_metrics.crest_exit_clock) < 0.0:
			current_metrics.crest_exit_clock = run_clock
		if skier.contact.grounded and total_hits == 4:
			current_metrics.runout_full_frames += 1
			if float(current_metrics.recontact_time) < 0.0:
				current_metrics.recontact_time = run_clock - float(current_metrics.crest_exit_clock)
	var discontinuity: Dictionary = skier.last_speed_discontinuity
	if not discontinuity.is_empty():
		current_metrics.speed_discontinuity = true
	for collider_name: String in skier.last_collision_colliders:
		if collider_name != "CrestBase" and collider_name != "RollerSurface":
			current_metrics.collision_count += 1
	if distance_along < float(current_metrics.last_distance) - 0.25:
		current_metrics.non_finite = true
	current_metrics.last_distance = distance_along

func _distance_along_roller() -> float:
	var roller_start := ParkLayout.snow_at(0.0, float(current_run.z))
	return (skier.global_position - roller_start).dot(ParkLayout.downhill())

func _required_full_contact_frames() -> int:
	return ceili(RUNOUT_FULL_CONTACT_SECONDS * Engine.physics_ticks_per_second)

func _finish_current_run() -> void:
	_release_inputs()
	var name_value := str(current_run.name)
	var mode_value := str(current_run.mode)
	var tip_excursion := float(current_metrics.tip_max) - float(current_metrics.tip_min)
	var normal_response := float(current_metrics.normal_velocity_max) - float(current_metrics.normal_velocity_min)
	var world_response := float(current_metrics.world_vertical_max) - float(current_metrics.world_vertical_min)
	var partial_seconds := float(current_metrics.max_partial_frames) / float(Engine.physics_ticks_per_second)
	var recontact_time := float(current_metrics.recontact_time)
	var strong_case := bool(current_run.strong)
	var summary := {
		"case": name_value,
		"mode": mode_value,
		"roller_length": float(current_run.length),
		"roller_height": float(current_run.height),
		"samples": int(current_metrics.sample_count),
		"front_contact_fraction": float(current_metrics.front_samples) / maxf(float(current_metrics.sample_count) * 2.0, 1.0),
		"rear_contact_fraction": float(current_metrics.rear_samples) / maxf(float(current_metrics.sample_count) * 2.0, 1.0),
		"min_total_contacts": int(current_metrics.min_total_contacts),
		"front_load_samples": int(current_metrics.front_load_samples),
		"rear_load_samples": int(current_metrics.rear_load_samples),
		"tip_min": float(current_metrics.tip_min),
		"tip_max": float(current_metrics.tip_max),
		"tip_excursion": tip_excursion,
		"crest_tip_min": float(current_metrics.crest_tip_min),
		"crest_tip_max": float(current_metrics.crest_tip_max),
		"normal_response": normal_response,
		"world_vertical_response": world_response,
		"air_frames": int(current_metrics.air_frames),
		"max_partial_seconds": partial_seconds,
		"recontact_seconds": recontact_time,
		"runout_full_frames": int(current_metrics.runout_full_frames),
		"speed_min": float(current_metrics.min_speed),
		"speed_max": float(current_metrics.max_speed),
		"collisions": int(current_metrics.collision_count),
		"speed_discontinuity": bool(current_metrics.speed_discontinuity),
		"trace": current_trace,
	}
	suite_results.append(summary)
	print("CREST_RESULT case=%s mode=%s front_samples=%d rear_samples=%d min_contacts=%d front_load_samples=%d rear_load_samples=%d tip_min=%.4f tip_max=%.4f tip_excursion=%.4f crest_tip_min=%.4f crest_tip_max=%.4f normal_response=%.4f world_vertical_response=%.4f air_frames=%d max_partial_seconds=%.4f recontact_seconds=%.4f speed=(%.3f,%.3f) collisions=%d discontinuity=%s" % [
		name_value,
		mode_value,
		int(current_metrics.front_samples),
		int(current_metrics.rear_samples),
		int(current_metrics.min_total_contacts),
		int(current_metrics.front_load_samples),
		int(current_metrics.rear_load_samples),
		float(current_metrics.tip_min),
		float(current_metrics.tip_max),
		tip_excursion,
		float(current_metrics.crest_tip_min),
		float(current_metrics.crest_tip_max),
		normal_response,
		world_response,
		int(current_metrics.air_frames),
		partial_seconds,
		recontact_time,
		float(current_metrics.min_speed),
		float(current_metrics.max_speed),
		int(current_metrics.collision_count),
		bool(current_metrics.speed_discontinuity),
	])
	if not bool(current_metrics.started):
		failures.append("%s/%s never entered the crest measurement window" % [name_value, mode_value])
	if bool(current_metrics.non_finite):
		failures.append("%s/%s produced a non-finite contact or motion metric" % [name_value, mode_value])
	if int(current_metrics.front_samples) == 0 or int(current_metrics.rear_samples) == 0:
		failures.append("%s/%s did not sample both front and rear probe pairs" % [name_value, mode_value])
	if mode_value == "CARVE" and not _trace_has_steering():
		failures.append("%s/%s did not exercise the deterministic analog steering input" % [name_value, mode_value])
	var required_tip_excursion := STRONG_TIP_LOAD_EXCURSION_MIN if strong_case else TIP_LOAD_EXCURSION_MIN
	if tip_excursion < required_tip_excursion:
		failures.append("%s/%s tip-load excursion %.4f was below %.4f" % [name_value, mode_value, tip_excursion, required_tip_excursion])
	var required_load_samples := 2 if strong_case else 1
	if int(current_metrics.front_load_samples) < required_load_samples or int(current_metrics.rear_load_samples) < required_load_samples:
		failures.append("%s/%s did not reverse signed front/rear loading across the crest" % [name_value, mode_value])
	if normal_response < VERTICAL_RESPONSE_MIN and world_response < VERTICAL_RESPONSE_MIN:
		failures.append("%s/%s vertical response was %.4f normal / %.4f world" % [name_value, mode_value, normal_response, world_response])
	var partial_support_limit := skier.profile.coyote_time + 1.0 / float(Engine.physics_ticks_per_second)
	if partial_seconds > partial_support_limit:
		failures.append("%s/%s remained grounded on partial support for %.4f seconds" % [name_value, mode_value, partial_seconds])
	if int(current_metrics.runout_full_frames) < _required_full_contact_frames():
		failures.append("%s/%s did not hold full four-probe runout contact for %.2f seconds" % [name_value, mode_value, RUNOUT_FULL_CONTACT_SECONDS])
	if recontact_time < 0.0 or recontact_time > RECONTACT_MAX_SECONDS:
		failures.append("%s/%s did not fully recontact the runout within %.2f seconds" % [name_value, mode_value, RECONTACT_MAX_SECONDS])
	if float(current_metrics.min_speed) < MIN_PROGRESS_SPEED:
		failures.append("%s/%s stalled at %.3f m/s" % [name_value, mode_value, float(current_metrics.min_speed)])
	if int(current_metrics.collision_count) > 0:
		failures.append("%s/%s had %d slide collisions" % [name_value, mode_value, int(current_metrics.collision_count)])
	if bool(current_metrics.speed_discontinuity):
		failures.append("%s/%s produced a speed discontinuity" % [name_value, mode_value])

func _trace_has_steering() -> bool:
	for sample: Dictionary in current_trace:
		if absf(float(sample.get("steering_input", 0.0))) >= 0.1:
			return true
	return false

func _fail_current_run(reason: String) -> void:
	failures.append("%s/%s %s" % [str(current_run.name), str(current_run.mode), reason])
	print("CREST_TIMEOUT case=%s mode=%s distance=%.3f" % [str(current_run.name), str(current_run.mode), _distance_along_roller()])

func _finish_suite() -> void:
	_release_inputs()
	print("CREST_PROFILE probe_offsets=%s tip_grip_gain=%.3f ticks=%d" % [
		skier.profile.contact_probe_offsets(),
		skier.profile.tip_grip_gain,
		Engine.physics_ticks_per_second,
	])
	_write_report()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CREST_PASS: roller crests produced measurable tip loading, vertical response, bounded partial support, and stable runout recontact")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CREST_FAIL: " + failure)
	get_tree().quit(1)

func _write_report() -> void:
	var report := {
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"start_speed": START_SPEED,
		"probe_offsets": skier.profile.contact_probe_offsets(),
		"tip_grip_gain": skier.profile.tip_grip_gain,
		"runs": suite_results,
	}
	var path := "user://crest_unweighting_results.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("Could not write crest trace report: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report))
	file.close()
	print("CREST_JSON_WRITTEN path=%s runs=%d" % [ProjectSettings.globalize_path(path), suite_results.size()])

func _release_inputs() -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
