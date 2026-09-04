extends Node

var failures: Array[String] = []

func _ready() -> void:
	var profile := ParkCourseProfile.new()
	var tracker := ParkChallengeTracker.new()
	add_child(tracker)
	tracker.configure(profile.challenge_specs())
	_validate_observation_only(tracker)
	_validate_grab_and_land(tracker)
	_validate_named_rail(tracker)
	_validate_sequence_and_route(tracker)
	_validate_bail_blocks_clean_attempt(tracker)
	_validate_any_rail(tracker)
	if failures.is_empty():
		print("PARK_CHALLENGE_ACCEPTANCE_PASS: data-driven challenges evaluate authoritative outcomes without gameplay mutation")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("PARK_CHALLENGE_ACCEPTANCE_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _validate_observation_only(tracker: ParkChallengeTracker) -> void:
	if tracker.has_method("apply_force") or tracker.has_method("resolve_landing"):
		failures.append("challenge tracker exposes gameplay mutation methods")

func _validate_grab_and_land(tracker: ParkChallengeTracker) -> void:
	tracker.begin_attempt(&"summit_fundamentals")
	tracker.record_event(&"air_rotation", {"degrees": 180.0})
	tracker.record_event(&"grab", {"active": true})
	tracker.record_event(&"landing", {"outcome": LandingSolver.Outcome.CLEAN})
	if not _completed(tracker, &"summit_grab_and_land"):
		failures.append("grab-and-land challenge did not complete")

func _validate_named_rail(tracker: ParkChallengeTracker) -> void:
	tracker.begin_attempt(&"technical_yard")
	tracker.record_event(&"rail_exit", {"feature_id": &"kink_rail", "captured": true})
	tracker.record_event(&"landing", {"outcome": LandingSolver.Outcome.CLEAN})
	if not _completed(tracker, &"technical_kink_clean"):
		failures.append("named-rail challenge did not complete")

func _validate_sequence_and_route(tracker: ParkChallengeTracker) -> void:
	tracker.begin_attempt(&"transfer_zone")
	tracker.record_event(&"feature_complete", {"feature_id": &"hip_transfer"})
	tracker.record_event(&"feature_complete", {"feature_id": &"transfer_box"})
	tracker.record_event(&"score", {"total_score": 1400})
	tracker.record_event(&"route_complete", {"route": &"expert"})
	if not _completed(tracker, &"transfer_expert_link"):
		failures.append("feature-sequence/route challenge did not complete")

func _validate_bail_blocks_clean_attempt(tracker: ParkChallengeTracker) -> void:
	tracker.begin_attempt(&"finale")
	tracker.record_event(&"air_rotation", {"degrees": 360.0})
	tracker.record_event(&"bail", {})
	tracker.record_event(&"landing", {"outcome": LandingSolver.Outcome.CLEAN})
	tracker.record_event(&"route_complete", {"route": &"expert"})
	if _completed(tracker, &"finale_clean_360"):
		failures.append("no-bail challenge completed after a bail")

func _completed(tracker: ParkChallengeTracker, challenge_id: StringName) -> bool:
	return bool(tracker.snapshot().get("completed", {}).get(challenge_id, false))

func _validate_any_rail(tracker: ParkChallengeTracker) -> void:
	var yard := SessionYardCourseProfile.new()
	tracker.configure(yard.challenge_specs())
	tracker.begin_attempt(&"session_yard")
	tracker.record_event(&"rail_capture", {"feature_id": &"yard_flat_box", "captured": true})
	tracker.record_event(&"landing", {"outcome": LandingSolver.Outcome.CLEAN})
	if not _completed(tracker, &"yard_any_rail"):
		failures.append("any-rail challenge did not complete")
