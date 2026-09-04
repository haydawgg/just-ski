class_name ParkChallengeTracker
extends Node

signal challenge_completed(challenge: ParkChallengeSpec)
signal attempt_changed(snapshot: Dictionary)

var _challenges: Array[ParkChallengeSpec] = []
var _completed: Dictionary = {}
var _active_spot_id: StringName
var _attempt := _empty_attempt()

func configure(challenges: Array[ParkChallengeSpec]) -> void:
	_challenges = challenges.duplicate()
	_completed.clear()
	_active_spot_id = &""
	_attempt = _empty_attempt()

func begin_attempt(spot_id: StringName) -> void:
	_active_spot_id = spot_id
	_attempt = _empty_attempt()
	_attempt["spot_id"] = spot_id
	attempt_changed.emit(snapshot())

func record_event(event_kind: StringName, payload: Dictionary = {}) -> void:
	if _active_spot_id == &"":
		return
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
			_attempt["total_score"] = maxi(int(_attempt.total_score), int(payload.get("total_score", 0)))
		&"route_complete":
			_attempt["completed_route"] = StringName(payload.get("route", &""))
		&"run_complete":
			_attempt["run_completed"] = true
	_evaluate()
	attempt_changed.emit(snapshot())

func snapshot() -> Dictionary:
	return {
		"active_spot_id": _active_spot_id,
		"attempt": _attempt.duplicate(true),
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
			return bool(_attempt.grabbed) and bool(_attempt.landed)
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
			return int(_attempt.total_score) >= int(condition.get("points", 0))
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
		"completed_route": &"",
		"run_completed": false,
	}
