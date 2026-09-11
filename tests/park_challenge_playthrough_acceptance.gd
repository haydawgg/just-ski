extends Node

var failures: Array[String] = []
var event_kinds: Array[StringName] = []
var event_features: Array[StringName] = []
var probe: SkierController
var content: ParkContentTracker
var sweep_active := false
var waypoints: Array[Vector2] = [
	Vector2(-12.0, 35.0),
	Vector2(-12.0, 12.0),
	Vector2(-26.0, 6.0),
	Vector2(-26.0, -20.0),
	Vector2(-1.0, -14.0),
	Vector2(-1.0, -36.0),
]
var waypoint_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_validate_course_geometry()
	await _validate_session_yard_terrain_only_flow()
	if failures.is_empty():
		print("PARK_CHALLENGE_PLAYTHROUGH_PASS: course geometry and ordered yard flow satisfy the authored challenges")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("PARK_CHALLENGE_PLAYTHROUGH_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _physics_process(_delta: float) -> void:
	if not sweep_active or probe == null or waypoint_index >= waypoints.size():
		return
	var target := waypoints[waypoint_index]
	var current := Vector2(probe.global_position.x, probe.global_position.z)
	var next := current + (target - current).limit_length(1.0)
	probe.global_position = Vector3(next.x, 6.0, next.y)
	if next.distance_to(target) < 0.001:
		waypoint_index += 1
		if waypoint_index >= waypoints.size():
			sweep_active = false

func _validate_course_geometry() -> void:
	for profile: ParkCourseProfile in [ParkCourseProfile.new(), SessionYardCourseProfile.new()]:
		var features: Dictionary = {}
		for spec: Dictionary in profile.feature_specs():
			features[StringName(spec.get("feature_id", &""))] = spec
		var finish_z := profile.finish_trigger_world_z()
		for challenge: ParkChallengeSpec in profile.challenge_specs():
			for condition: Dictionary in challenge.conditions:
				var required: Array = []
				match StringName(condition.get("kind", &"")):
					&"feature_sequence":
						required = condition.get("feature_ids", []) as Array
					&"grind":
						var grind_id := StringName(condition.get("feature_id", &""))
						if grind_id != &"":
							required.append(grind_id)
				for feature_id: StringName in required:
					var spec: Dictionary = features.get(feature_id, {})
					if spec.is_empty():
						failures.append("%s references unknown feature %s" % [challenge.id, feature_id])
						continue
					var threshold_z := ParkContentTracker.feature_course_position(spec).z - ParkContentTracker.FEATURE_COMPLETE_DOWNHILL_DISTANCE
					# The finish box entry sits ~3 m uphill of its center; it
					# must not preempt a required feature completion.
					if finish_z + 3.0 >= threshold_z:
						failures.append(
							"%s: finish z %.1f is not downhill of %s completion threshold %.1f"
							% [challenge.id, finish_z, feature_id, threshold_z]
						)

func _validate_session_yard_terrain_only_flow() -> void:
	probe = SkierController.new()
	probe.set_physics_process(false)
	add_child(probe)
	probe.global_position = Vector3(-12.0, 6.0, 35.0)
	content = ParkContentTracker.new()
	add_child(content)
	content.telemetry_enabled = false
	content.content_event_recorded.connect(func(event: Dictionary) -> void:
		event_kinds.append(StringName(event.get("kind", &"")))
		event_features.append(StringName(event.get("feature_id", &"")))
	)
	content.configure(SessionYardCourseProfile.new(), probe)
	await get_tree().physics_frame
	if content.active_spot == null or content.active_spot.id != &"session_yard":
		failures.append("Session Yard spot did not activate for the probe")
		return
	sweep_active = true
	# The polyline threads between the intermediate/expert approach circles so
	# only safe-route features complete; the terrain line completes below
	# z = -33, before the run can finish.
	if not await _wait_for(func() -> bool: return _feature_completed(&"yard_terrain_line"), 400):
		failures.append("The clean-line sweep never completed the yard terrain line")
		return
	var completed_before_finish := _completed_challenge(&"yard_terrain_only")
	if completed_before_finish:
		failures.append("Terrain Only completed before the run finished")
	probe.scoring.finish_run()
	if not _completed_challenge(&"yard_terrain_only"):
		failures.append("Terrain Only did not complete when the run finished after the terrain line")
	if not _ordered_after(&"yard_terrain_line", &"run_complete"):
		failures.append("Terrain line completion was not followed by the run completion event")
	if not _ordered_after(&"yard_setup_roller", &"yard_small_jump") or not _ordered_after(&"yard_small_jump", &"yard_terrain_line"):
		failures.append("Terrain Only feature sequence completed out of order")
	var attempt := (content.challenge_tracker.snapshot().get("attempt", {}) as Dictionary)
	if StringName(attempt.get("completed_route", &"")) != &"safe":
		failures.append("The clean-line sweep credited a non-safe route (%s)" % str(attempt.get("completed_route", &"")))
	if _completed_challenge(&"yard_any_rail"):
		failures.append("Terrain Only sweep awarded the rail challenge")

func _feature_completed(feature_id: StringName) -> bool:
	for index: int in event_kinds.size():
		if event_kinds[index] == &"feature_complete" and event_features[index] == feature_id:
			return true
	return false

func _ordered_after(first: StringName, second: StringName) -> bool:
	var first_index := -1
	var second_index := -1
	for index: int in event_kinds.size():
		if first_index < 0 and event_kinds[index] == &"feature_complete" and event_features[index] == first:
			first_index = index
		if event_kinds[index] == second or (event_kinds[index] == &"feature_complete" and event_features[index] == second):
			second_index = index
	return first_index >= 0 and second_index > first_index

func _completed_challenge(challenge_id: StringName) -> bool:
	var snapshot := content.challenge_tracker.snapshot()
	return bool((snapshot.get("completed", {}) as Dictionary).get(challenge_id, false))

func _wait_for(predicate: Callable, budget_frames: int) -> bool:
	var frames := budget_frames
	while frames > 0:
		if predicate.call():
			return true
		await get_tree().physics_frame
		frames -= 1
	return predicate.call()
