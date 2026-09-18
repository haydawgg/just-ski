extends Node

const PHYSICS_PROFILE: SkiPhysicsProfile = preload("res://resources/physics/default_ski_profile.tres")
const SESSION_YARD: SessionYardCourseProfile = preload("res://resources/course/session_yard_course_profile.tres")
const ASSET_CATALOG: EnvironmentAssetCatalog = preload("res://resources/environment/default_environment_asset_catalog.tres")

var failures: Array[String] = []

func _ready() -> void:
	_validate_runtime_metadata_and_equivalence(ParkCourseProfile.new())
	_validate_session_yard()
	_validate_local_telemetry()
	if failures.is_empty():
		print("PARK_CONTENT_RUNTIME_PASS: runtime metadata, deterministic builds, Session Yard, and local telemetry validated")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("PARK_CONTENT_RUNTIME_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _validate_runtime_metadata_and_equivalence(profile: ParkCourseProfile) -> void:
	var first_root := Node3D.new()
	var second_root := Node3D.new()
	add_child(first_root)
	add_child(second_root)
	var first := ParkCourseBuilder.build(first_root, profile, PHYSICS_PROFILE)
	var second := ParkCourseBuilder.build(second_root, profile, PHYSICS_PROFILE)
	if first.keys() != second.keys():
		failures.append("repeated course builds changed deterministic ordering")
	if first.size() != profile.feature_specs().size():
		failures.append("runtime build count differs from source profile")
	var side_hits := 0
	for feature_name: String in first:
		var feature := first[feature_name] as Node3D
		for key: String in ["feature_id", "spot_id", "route", "discipline", "skill_floor", "skill_ceiling", "intent_tags", "risk_level", "hero_feature", "optional"]:
			if feature == null or not feature.has_meta(key):
				failures.append("%s is missing runtime content metadata %s" % [feature_name, key])
		if feature_name in ["UpperLeftSideHit", "CenterSpine", "LowerRightSideHit"]:
			side_hits += 1
			if feature.find_children("*", "MeshInstance3D", true, false).is_empty() or feature.find_children("*", "CollisionShape3D", true, false).is_empty():
				failures.append("side hit %s lacks shared render/collision geometry" % feature_name)
	if side_hits != 3:
		failures.append("expected three side hits, found %d" % side_hits)
	first_root.queue_free()
	second_root.queue_free()

func _validate_session_yard() -> void:
	var errors := SESSION_YARD.validate_content()
	for error: String in errors:
		failures.append("Session Yard validation: " + error)
	var specs := SESSION_YARD.feature_specs()
	if specs.size() < 8:
		failures.append("Session Yard lacks a useful rapid-retry feature set")
	var kinds: Dictionary = {}
	var routes: Dictionary = {}
	var disciplines: Dictionary = {}
	for spec: Dictionary in specs:
		kinds[StringName(spec.kind)] = true
		routes[StringName(spec.route)] = true
		disciplines[StringName(spec.discipline)] = true
	for required_kind: StringName in [&"tabletop", &"rail", &"berm", &"side_hit", &"butter"]:
		if not kinds.has(required_kind):
			failures.append("Session Yard is missing %s content" % required_kind)
	for required_route: StringName in [&"safe", &"intermediate", &"expert"]:
		if not routes.has(required_route):
			failures.append("Session Yard is missing %s route" % required_route)
	for required_discipline: StringName in [&"air", &"jib", &"flow"]:
		if not disciplines.has(required_discipline):
			failures.append("Session Yard is missing %s discipline" % required_discipline)
	var first_root := Node3D.new()
	var second_root := Node3D.new()
	add_child(first_root)
	add_child(second_root)
	var first := ParkCourseBuilder.build(first_root, SESSION_YARD, PHYSICS_PROFILE, ASSET_CATALOG)
	var second := ParkCourseBuilder.build(second_root, SESSION_YARD, PHYSICS_PROFILE, ASSET_CATALOG)
	if first.keys() != second.keys() or first.size() != specs.size():
		failures.append("Session Yard construction is not deterministic")
	for feature_name: String in first:
		var feature := first[feature_name] as Node3D
		if feature == null or str(feature.get_meta("asset_source", "")) not in ["production_scene", "project_authored_parametric_scene"]:
			failures.append("Session Yard feature %s did not satisfy the production asset contract" % feature_name)
		if feature == null or not feature.has_meta("discipline"):
			failures.append("Session Yard feature %s did not propagate discipline metadata" % feature_name)
	first_root.queue_free()
	second_root.queue_free()

func _validate_local_telemetry() -> void:
	var tracker := ParkContentTracker.new()
	tracker.telemetry_enabled = true
	add_child(tracker)
	tracker.configure(ParkCourseProfile.new())
	tracker.record_event(&"feature_approach", {"feature_id": &"small_table"})
	tracker.record_event(&"rail_capture", {"feature_id": &"summit_flat_box", "captured": true})
	tracker.observe_camera_snapshot({
		"camera_fallback_count": 2,
		"state": "GROUND",
		"target_distance": 4.8,
		"composition_recovery_active": true,
		"camera_occluded": false,
		"foreground_occlusion_fraction": 0.15,
		"carve_look_ahead_offset": Vector3(0.3, 0.0, 0.4),
	}, {"state": "GROUND", "speed_mps": 14.0})
	# Re-observing the same cumulative total must not double-count it.
	tracker.observe_camera_snapshot({
		"camera_fallback_count": 2,
		"state": "GROUND",
		"carve_look_ahead_offset": Vector3(0.3, 0.0, 0.4),
	})
	tracker.observe_camera_snapshot({
		"camera_fallback_count": 3,
		"state": "AIR",
		"target_distance": 5.2,
	}, {"state": "AIR", "speed_mps": 16.0})
	tracker._on_landed({
		"outcome": LandingSolver.Outcome.HARD,
		"score": 0.42,
		"impact": 5.1,
		"impact_severity": 0.8,
		"balance_error": 0.4,
		"ski_alignment_error": 0.2,
		"body_roll_error": 0.1,
		"body_pitch_error": 0.15,
		"rotation_residual_degrees": -37.3,
		"rotation_quality": 0.84,
		"rotation_orientation_error_degrees": 12.0,
	})
	tracker._on_trick_landed("Left 180", 420, 0.84, LandingSolver.Outcome.HARD)
	tracker.record_event(&"marker_save", {"position": Vector3.ZERO})
	tracker.record_event(&"marker_return", {"position": Vector3.ZERO})
	tracker.record_event(&"run_complete", {"total_score": 1000})
	var snapshot := tracker.snapshot()
	if StringName(snapshot.get("active_spot_id", &"")) != &"summit_fundamentals":
		failures.append("content tracker did not initialize the first spot")
	if int((snapshot.get("attempt_counts", {}) as Dictionary).get(&"summit_fundamentals", 0)) != 1:
		failures.append("content tracker did not count the spot attempt")
	var diagnostics_by_spot := snapshot.get("spot_diagnostics", {}) as Dictionary
	var diagnostics := diagnostics_by_spot.get(&"summit_fundamentals", {}) as Dictionary
	if int(diagnostics.get("camera_fallback_count", -1)) != 3:
		failures.append("spot diagnostics did not accumulate camera fallback deltas")
	if int(diagnostics.get("camera_fallback_event_count", -1)) != 2:
		failures.append("spot diagnostics double-counted an unchanged camera fallback total")
	var fallback_states := diagnostics.get("camera_fallbacks_by_state", {}) as Dictionary
	if int(fallback_states.get("GROUND", 0)) != 2 or int(fallback_states.get("AIR", 0)) != 1:
		failures.append("spot diagnostics did not classify camera fallbacks by state")
	if not is_equal_approx(float(diagnostics.get("max_carve_look_ahead_m", 0.0)), 0.5):
		failures.append("spot diagnostics did not retain peak carve look-ahead")
	var landing := diagnostics.get("last_landing", {}) as Dictionary
	if str(landing.get("outcome_name", "")) != "HARD" or not is_equal_approx(float(landing.get("rotation_residual_degrees", 0.0)), -37.3):
		failures.append("spot diagnostics lost normalized landing outcome/residual feedback")
	var trick := diagnostics.get("last_trick", {}) as Dictionary
	if str(trick.get("name", "")) != "Left 180" or int(trick.get("points", 0)) != 420:
		failures.append("spot diagnostics lost landed trick feedback")
	var kinds: Dictionary = {}
	for event: Dictionary in snapshot.get("trace_events", []):
		kinds[StringName(event.get("kind", &""))] = true
	for expected: StringName in [&"spot_entry", &"feature_approach", &"rail_capture", &"camera_fallback", &"landing", &"landing_feedback", &"trick_feedback", &"marker_save", &"marker_return", &"run_complete"]:
		if not kinds.has(expected):
			failures.append("local telemetry omitted %s" % expected)
