extends "res://tests/continuous_course_release_acceptance.gd"

## Strict integrated follow-up for the uninterrupted release trace. The base
## fixture remains the deterministic 60 Hz evidence path; this subclass adds
## 30/60/120 Hz scene variants and gates the production behaviors that a
## design-only jump-table test cannot prove: increasing real jump progression,
## clean nominal landings, usable setup time, a clean hero runout, and bounded
## camera recovery activity.

const MATRIX_TRACE_VERSION := "continuous_course_release/v2"
const MIN_SETUP_AFTER_STABLE_SECONDS := 2.0
const MIN_LIP_SPEED_STEP_MPS := 0.20
const MIN_AIRTIME_STEP_SECONDS := 0.04
const MAX_RAW_INVALID_STREAK_SECONDS := 0.12
const MAX_FALLBACKS_PER_SECOND := 4.0
const MAX_CONSECUTIVE_EMERGENCY_FRAMES := 3
const POST_LARGE_AIR_GRACE_SECONDS := 0.35
const MAX_POST_LARGE_AIR_SECONDS := 0.20
const MIN_POST_LARGE_GROUNDED_STREAK_SECONDS := 3.5

@export_range(30, 120, 30) var acceptance_physics_hz := 60

var raw_composition_invalid_frames := 0
var recovery_composition_invalid_frames := 0
var current_raw_invalid_streak := 0
var maximum_raw_invalid_streak := 0
var maximum_consecutive_emergencies := 0
var hard_reacquire_frames := 0
var emergency_fallback_frames := 0
var post_large_air_frames := 0
var post_large_current_grounded_frames := 0
var post_large_max_grounded_frames := 0

func _enter_tree() -> void:
	Engine.physics_ticks_per_second = acceptance_physics_hz

func _build_course_trace() -> void:
	super._build_course_trace()
	for record: Dictionary in jump_records:
		record["stable_recovery_frame"] = -1
		record["setup_after_stable_seconds"] = -1.0

func _apply_controls() -> void:
	super._apply_controls()
	if skier == null or skier.state == SkierController.State.BAIL:
		return

	# Normal gameplay is allowed to tuck to build the progressively larger
	# approach speeds. This is not a velocity write: it exercises the production
	# drag/input path and stops before the takeoff zone so the skier can extend.
	if next_jump_index < HERO_JUMPS.size() and skier.state == SkierController.State.GROUND:
		var entry := jump_specs[next_jump_index]
		var spec := entry.spec as Dictionary
		var geometry := entry.geometry as Dictionary
		var distance_to_lip := skier.global_position.z - float(geometry.lip_edge_z)
		var target_speed := float(spec.speed)
		if distance_to_lip > 15.0 and skier.velocity.length() < target_speed - 0.25:
			Input.action_press("tuck", 1.0)

	# The hero line remains on the authored jump lane after LargeTable. The v1
	# driver returned toward x=0, which could cross finale side content and
	# manufacture extra AIR states in what is meant to be the clean runout.
	if next_jump_index >= HERO_JUMPS.size() and not jump_specs.is_empty() and skier.state == SkierController.State.GROUND:
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		var hero_x := float((jump_specs[-1].spec as Dictionary).x)
		var predicted_x := skier.global_position.x + skier.velocity.x * 0.45
		var line_error := predicted_x - hero_x
		if absf(line_error) > 0.28:
			var action := "steer_left" if line_error > 0.0 else "steer_right"
			Input.action_press(action, clampf(absf(line_error) / 10.0, 0.16, 0.48))

func _sample_frame() -> void:
	super._sample_frame()
	if skier == null or camera == null:
		return

	var snapshot := camera.debug_snapshot()
	var composition_valid := bool(snapshot.get("composition_valid", true))
	var recovery_active := bool(snapshot.get("composition_recovery_active", false))
	if not composition_valid:
		raw_composition_invalid_frames += 1
		current_raw_invalid_streak += 1
		maximum_raw_invalid_streak = maxi(maximum_raw_invalid_streak, current_raw_invalid_streak)
		if recovery_active:
			recovery_composition_invalid_frames += 1
	else:
		current_raw_invalid_streak = 0
	maximum_consecutive_emergencies = maxi(maximum_consecutive_emergencies, int(snapshot.get("consecutive_emergency_frames", 0)))
	if bool(snapshot.get("hard_reacquire_used", false)):
		hard_reacquire_frames += 1
	if bool(snapshot.get("emergency_fallback_used", false)):
		emergency_fallback_frames += 1

	# Capture the first frame at which each landed jump has sustained the stable
	# grounded window. Unlike the v1 value, this preserves the absolute frame so
	# the next takeoff can measure usable setup time after stability was regained.
	if active_jump_index < 0 and next_jump_index > 0:
		var landed_index := mini(next_jump_index - 1, jump_records.size() - 1)
		if landed_index >= 0:
			var recovery := jump_records[landed_index]
			if int(recovery.get("stable_recovery_frame", -1)) < 0 and int(recovery.get("current_grounded_frames", 0)) >= int(ceil(MIN_STABLE_GROUND_SECONDS * physics_hz)):
				recovery["stable_recovery_frame"] = frame_index
				recovery["stable_recovery_seconds"] = float(frame_index - int(recovery.landing_frame)) / physics_hz

	# Once a later jump takes off, convert the preceding stable-frame marker into
	# the actual setup interval available to the player.
	for index: int in range(1, jump_records.size()):
		var current := jump_records[index]
		var prior := jump_records[index - 1]
		if int(current.takeoff_frame) == frame_index and int(prior.get("stable_recovery_frame", -1)) >= 0:
			prior["setup_after_stable_seconds"] = float(frame_index - int(prior.stable_recovery_frame)) / physics_hz

	if post_large_landing_frame >= 0:
		var frames_after_large := frame_index - post_large_landing_frame
		var grace_frames := int(ceil(POST_LARGE_AIR_GRACE_SECONDS * physics_hz))
		if frames_after_large > grace_frames:
			if skier.state == SkierController.State.GROUND and skier.contact.grounded:
				post_large_current_grounded_frames += 1
				post_large_max_grounded_frames = maxi(post_large_max_grounded_frames, post_large_current_grounded_frames)
			elif skier.state == SkierController.State.AIR:
				post_large_air_frames += 1
				post_large_current_grounded_frames = 0
			else:
				post_large_current_grounded_frames = 0

func _validate_trace() -> void:
	super._validate_trace()
	if jump_records.size() != HERO_JUMPS.size():
		return

	var previous_speed := -INF
	var previous_airtime := -INF
	for index: int in range(jump_records.size()):
		var record := jump_records[index]
		var result := record.get("landing_result", {}) as Dictionary
		if int(result.get("outcome", LandingSolver.Outcome.BAIL)) != LandingSolver.Outcome.CLEAN:
			failures.append("%s nominal landing outcome was %s, expected CLEAN" % [record.name, str(result.get("outcome", -1))])
		if bool(result.get("hard_failure", true)):
			failures.append("%s nominal landing reported hard_failure" % record.name)
		var speed := float(record.lip_speed_mps)
		var airtime := float(record.airtime_seconds)
		if index > 0 and speed < previous_speed + MIN_LIP_SPEED_STEP_MPS:
			failures.append("Real lip-speed progression stalled at %s: %.2f after %.2f m/s" % [record.name, speed, previous_speed])
		if index > 0 and airtime < previous_airtime + MIN_AIRTIME_STEP_SECONDS:
			failures.append("Real airtime progression stalled at %s: %.2f after %.2f s" % [record.name, airtime, previous_airtime])
		previous_speed = speed
		previous_airtime = airtime
		if index < jump_records.size() - 1 and float(record.get("setup_after_stable_seconds", -1.0)) < MIN_SETUP_AFTER_STABLE_SECONDS:
			failures.append("%s provided only %.2f s of setup after stable recovery (need %.2f s)" % [record.name, float(record.get("setup_after_stable_seconds", -1.0)), MIN_SETUP_AFTER_STABLE_SECONDS])

	var raw_invalid_seconds := float(maximum_raw_invalid_streak) / physics_hz
	if raw_invalid_seconds > MAX_RAW_INVALID_STREAK_SECONDS:
		failures.append("Camera raw invalid streak lasted %.3f s (limit %.3f s)" % [raw_invalid_seconds, MAX_RAW_INVALID_STREAK_SECONDS])
	if maximum_consecutive_emergencies > MAX_CONSECUTIVE_EMERGENCY_FRAMES:
		failures.append("Camera emergency streak reached %d frames (limit %d)" % [maximum_consecutive_emergencies, MAX_CONSECUTIVE_EMERGENCY_FRAMES])
	var duration_seconds := maxf(float(frame_index) / physics_hz, 0.001)
	var fallback_rate := float(camera_fallback_count) / duration_seconds
	if fallback_rate > MAX_FALLBACKS_PER_SECOND:
		failures.append("Camera fallback rate %.2f/s exceeded %.2f/s" % [fallback_rate, MAX_FALLBACKS_PER_SECOND])
	var post_large_air_seconds := float(post_large_air_frames) / physics_hz
	if post_large_air_seconds > MAX_POST_LARGE_AIR_SECONDS:
		failures.append("Hero runout spent %.2f s airborne after grace (limit %.2f s)" % [post_large_air_seconds, MAX_POST_LARGE_AIR_SECONDS])
	var grounded_streak_seconds := float(post_large_max_grounded_frames) / physics_hz
	if grounded_streak_seconds < MIN_POST_LARGE_GROUNDED_STREAK_SECONDS:
		failures.append("Hero runout longest grounded streak was %.2f s (need %.2f s)" % [grounded_streak_seconds, MIN_POST_LARGE_GROUNDED_STREAK_SECONDS])

func _write_profile() -> void:
	super._write_profile()
	var matrix_jumps: Array[Dictionary] = []
	for record: Dictionary in jump_records:
		matrix_jumps.append({
			"name": record.name,
			"lip_speed_mps": record.lip_speed_mps,
			"airtime_seconds": record.airtime_seconds,
			"landing_outcome": int((record.get("landing_result", {}) as Dictionary).get("outcome", -1)),
			"stable_recovery_seconds": record.get("stable_recovery_seconds", -1.0),
			"setup_after_stable_seconds": record.get("setup_after_stable_seconds", -1.0),
		})
	var payload := {
		"trace_version": MATRIX_TRACE_VERSION,
		"physics_hz": physics_hz,
		"duration_seconds": float(frame_index) / physics_hz,
		"jumps": matrix_jumps,
		"camera": {
			"raw_invalid_frames": raw_composition_invalid_frames,
			"recovery_invalid_frames": recovery_composition_invalid_frames,
			"maximum_raw_invalid_streak_frames": maximum_raw_invalid_streak,
			"fallback_count": camera_fallback_count,
			"maximum_consecutive_emergencies": maximum_consecutive_emergencies,
			"hard_reacquire_frames": hard_reacquire_frames,
			"emergency_fallback_frames": emergency_fallback_frames,
		},
		"runout": {
			"post_large_air_seconds": float(post_large_air_frames) / physics_hz,
			"maximum_grounded_streak_seconds": float(post_large_max_grounded_frames) / physics_hz,
		},
		"failures": failures,
	}
	var path := "user://continuous_course_release_matrix_%dhz.json" % int(round(physics_hz))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("Could not write matrix release telemetry")
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("CONTINUOUS_MATRIX_SUMMARY hz=%d profile=%s data=%s" % [int(round(physics_hz)), ProjectSettings.globalize_path(path), JSON.stringify(payload)])
