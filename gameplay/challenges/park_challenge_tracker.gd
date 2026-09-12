class_name ParkChallengeTracker
extends Node

signal challenge_completed(challenge: ParkChallengeSpec)
signal attempt_changed(snapshot: Dictionary)

const MAX_ATTEMPT_EVENTS := 256

var _challenges: Array[ParkChallengeSpec] = []
var _completed: Dictionary = {}
var _active_spot_id: StringName
var _attempt := _empty_attempt()

func configure(challenges: Array[ParkChallengeSpec]) -> void:
	_challenges = challenges.duplicate()
	_completed.clear()
	_active_spot_id = &""
	_attempt = _empty_attempt()

func begin_attempt(spot_id: StringName, attempt_start_score := 0) -> void:
	_active_spot_id = spot_id
	_attempt = _empty_attempt()
	_attempt["spot_id"] = spot_id
	_attempt["attempt_start_score"] = attempt_start_score
	attempt_changed.emit(snapshot())

func record_event(event_kind: StringName, payload: Dictionary = {}) -> void:
	if _active_spot_id == &"":
		return
	_log_attempt_event(event_kind, payload)
	match event_kind:
		&"air_rotation":
			_attempt["rotation_degrees"] = maxf(float(_attempt.rotation_degrees), absf(float(payload.get("degrees", 0.0))))
		&"grab":
			_attempt["grabbed"] = bool(_attempt.grabbed) or bool(payload.get("active", true))
		&"landing":
			_attempt["landed"] = true
			_attempt["clean_landing"] = int(payload.get("outcome", -1)) == LandingSolver.Outcome.CLEAN
		&"rail_capture":
			if bool(payload.get("captured", true)):
				_record_rail(StringName(payload.get("feature_id", &"")))
		&"rail_exit":
			if bool(payload.get("captured", true)):
				_record_rail(StringName(payload.get("feature_id", &"")))
		&"feature_complete":
			_append_feature(StringName(payload.get("feature_id", &"")))
		&"bail":
			_attempt["bailed"] = true
		&"score":
			var total := int(payload.get("total_score", 0))
			_attempt["total_score"] = maxi(int(_attempt.total_score), total)
			_attempt["score_earned"] = maxi(int(_attempt.score_earned), total - int(_attempt.attempt_start_score))
		&"route_complete":
			_attempt["completed_route"] = StringName(payload.get("route", &""))
		&"run_complete":
			_attempt["run_completed"] = true
	_evaluate()
	attempt_changed.emit(snapshot())

func snapshot() -> Dictionary:
	# The event log is internal ordering machinery and stays out of UI snapshots.
	var published_attempt := _attempt.duplicate(true)
	published_attempt.erase("event_log")
	return {
		"active_spot_id": _active_spot_id,
		"attempt": published_attempt,
		"completed": _completed.duplicate(),
		"available": challenges_for_spot(_active_spot_id),
	}

func challenges_for_spot(spot_id: StringName) -> Array[ParkChallengeSpec]:
	var result: Array[ParkChallengeSpec] = []
	for challenge: ParkChallengeSpec in _challenges:
		if challenge.spot_id == spot_id:
			result.append(challenge)
	return result

func _evaluate() -> void:
	for challenge: ParkChallengeSpec in challenges_for_spot(_active_spot_id):
		if bool(_completed.get(challenge.id, false)):
			continue
		var valid := true
		for condition: Dictionary in challenge.conditions:
			if not _condition_met(condition):
				valid = false
				break
		if valid:
			_completed[challenge.id] = true
			challenge_completed.emit(challenge)

func _condition_met(condition: Dictionary) -> bool:
	match StringName(condition.get("kind", &"")):
		&"air_rotation":
			var degrees := float(_attempt.rotation_degrees)
			return degrees >= float(condition.get("minimum_degrees", 0.0)) and degrees <= float(condition.get("maximum_degrees", INF))
		&"grab_and_land":
			var anchor: Dictionary = condition.get("after", {})
			if anchor.is_empty():
				return bool(_attempt.grabbed) and bool(_attempt.landed)
			var anchor_index := _anchor_index(anchor)
			if anchor_index < 0:
				return false
			var grab_index := _event_index_after(&"grab", anchor_index)
			if grab_index < 0:
				return false
			return _event_index_after(&"landing", grab_index) >= 0
		&"grind":
			var required := StringName(condition.get("feature_id", &""))
			return not (_attempt.rails as Array).is_empty() if required == &"" else required in (_attempt.rails as Array)
		&"feature_sequence":
			return _contains_ordered_sequence(_attempt.features as Array, condition.get("feature_ids", []) as Array)
		&"clean_landing":
			return bool(_attempt.clean_landing)
		&"no_bail":
			return not bool(_attempt.bailed)
		&"minimum_score":
			return int(_attempt.score_earned) >= int(condition.get("points", 0))
		&"finish_route":
			return StringName(_attempt.completed_route) == StringName(condition.get("route", &""))
		&"run_complete":
			return bool(_attempt.run_completed)
	return false

func _record_rail(feature_id: StringName) -> void:
	if feature_id == &"":
		return
	if feature_id not in (_attempt.rails as Array):
		(_attempt.rails as Array).append(feature_id)
	_append_feature(feature_id)

func _append_feature(feature_id: StringName) -> void:
	if feature_id != &"":
		(_attempt.features as Array).append(feature_id)

func _contains_ordered_sequence(actual: Array, required: Array) -> bool:
	if required.is_empty():
		return true
	var cursor := 0
	for value: Variant in actual:
		if StringName(value) == StringName(required[cursor]):
			cursor += 1
			if cursor >= required.size():
				return true
	return false

func _empty_attempt() -> Dictionary:
	return {
		"spot_id": &"",
		"rotation_degrees": 0.0,
		"grabbed": false,
		"landed": false,
		"clean_landing": false,
		"rails": [],
		"features": [],
		"bailed": false,
		"total_score": 0,
		"attempt_start_score": 0,
		"score_earned": 0,
		"completed_route": &"",
		"run_completed": false,
		"event_log": [],
	}

func _log_attempt_event(event_kind: StringName, payload: Dictionary) -> void:
	var log := _attempt.event_log as Array
	log.append({
		"kind": event_kind,
		"feature_id": StringName(payload.get("feature_id", &"")),
	})
	if log.size() > MAX_ATTEMPT_EVENTS:
		log.pop_front()

func _anchor_index(anchor: Dictionary) -> int:
	var kind := StringName(anchor.get("kind", &""))
	var feature_id := StringName(anchor.get("feature_id", &""))
	# Condition vocabulary maps onto recorded event kinds.
	if kind == &"grind":
		kind = &"rail_capture"
	var log := _attempt.event_log as Array
	for index: int in log.size():
		var entry: Dictionary = log[index]
		if StringName(entry.get("kind", &"")) != kind:
			continue
		if feature_id != &"" and StringName(entry.get("feature_id", &"")) != feature_id:
			continue
		return index
	return -1

func _event_index_after(kind: StringName, after_index: int) -> int:
	var log := _attempt.event_log as Array
	for index: int in range(after_index + 1, log.size()):
		if StringName((log[index] as Dictionary).get("kind", &"")) == kind:
			return index
	return -1
