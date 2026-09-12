class_name ParkContentTracker
extends Node

signal spot_changed(spot: ParkSpotSpec)
signal challenge_updated(snapshot: Dictionary)
signal content_event_recorded(event: Dictionary)

const MAX_TRACE_EVENTS := 256
const FEATURE_APPROACH_DISTANCE := 13.0
const FEATURE_COMPLETE_DOWNHILL_DISTANCE := 5.0

var telemetry_enabled := OS.is_debug_build() or OS.get_cmdline_user_args().has("--content-trace")
var challenge_tracker := ParkChallengeTracker.new()
var active_spot: ParkSpotSpec
var attempt_counts: Dictionary = {}
var trace_events: Array[Dictionary] = []

var _profile: ParkCourseProfile
var _player: SkierController
var _spots: Array[ParkSpotSpec] = []
var _features: Dictionary = {}
var _approached: Dictionary = {}
var _completed_in_attempt: Dictionary = {}
var _route_features: Array[StringName] = []
var _attempt_start_score := 0
var _last_state := ""
var _last_rail_feature_id: StringName
var _last_rotation_degrees := 0.0
var _last_grab_active := false

func _ready() -> void:
	challenge_tracker.name = "ChallengeTracker"
	add_child(challenge_tracker)
	challenge_tracker.challenge_completed.connect(_on_challenge_completed)
	challenge_tracker.attempt_changed.connect(func(snapshot: Dictionary) -> void: challenge_updated.emit(snapshot))

func configure(profile: ParkCourseProfile, player: SkierController = null) -> void:
	_disconnect_player()
	_profile = profile
	_player = player
	_spots = profile.spot_specs() if profile != null else []
	_features.clear()
	if profile != null:
		for spec: Dictionary in profile.feature_specs():
			_features[StringName(spec.get("feature_id", &""))] = spec
		challenge_tracker.configure(profile.challenge_specs())
	if _player != null:
		_player.state_changed.connect(_on_state_changed)
		_player.rail_finished.connect(_on_rail_finished)
		_player.telemetry_updated.connect(_on_player_telemetry)
		_player.landed.connect(_on_landed)
		_player.crashed.connect(_on_crashed)
		_player.respawn_applied.connect(_on_respawn_applied)
		_player.scoring.score_changed.connect(_on_score_changed)
		_player.scoring.run_finished.connect(_on_run_finished)
	if not SessionManager.marker_changed.is_connected(_on_marker_changed):
		SessionManager.marker_changed.connect(_on_marker_changed)
	_update_active_spot(true)

func _exit_tree() -> void:
	_disconnect_player()
	if SessionManager.marker_changed.is_connected(_on_marker_changed):
		SessionManager.marker_changed.disconnect(_on_marker_changed)

func _physics_process(_delta: float) -> void:
	if _player == null or _profile == null:
		return
	_update_active_spot(false)
	_update_feature_flow()

func record_event(kind: StringName, payload: Dictionary = {}) -> void:
	var event := payload.duplicate(true)
	event["kind"] = kind
	event["spot_id"] = active_spot.id if active_spot != null else &""
	if telemetry_enabled:
		event["physics_frame"] = Engine.get_physics_frames()
		trace_events.append(event)
		if trace_events.size() > MAX_TRACE_EVENTS:
			trace_events.pop_front()
	content_event_recorded.emit(event)
	challenge_tracker.record_event(kind, payload)

func snapshot() -> Dictionary:
	return {
		"active_spot_id": active_spot.id if active_spot != null else &"",
		"active_spot_name": active_spot.display_name if active_spot != null else "",
		"attempt_counts": attempt_counts.duplicate(),
		"route_features": _route_features.duplicate(),
		"challenge": challenge_tracker.snapshot(),
		"trace_events": trace_events.duplicate(true) if telemetry_enabled else [],
	}

func _update_active_spot(force: bool) -> void:
	if _spots.is_empty():
		return
	var position := _player.global_position if _player != null else Vector3(_spots[0].anchor.x, 0.0, _spots[0].anchor.z)
	var nearest: ParkSpotSpec
	var nearest_distance := INF
	for spot: ParkSpotSpec in _spots:
		var distance := Vector2(position.x - spot.anchor.x, position.z - spot.anchor.z).length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = spot
	if nearest == null or (not force and nearest == active_spot):
		return
	if active_spot != null and active_spot != nearest:
		_complete_route()
	active_spot = nearest
	_approached.clear()
	_completed_in_attempt.clear()
	_route_features.clear()
	_last_rotation_degrees = 0.0
	_last_grab_active = false
	_attempt_start_score = 0
	if _player != null and _player.scoring != null:
		_attempt_start_score = int(_player.scoring.total_score)
	attempt_counts[active_spot.id] = int(attempt_counts.get(active_spot.id, 0)) + 1
	challenge_tracker.begin_attempt(active_spot.id, _attempt_start_score)
	record_event(&"spot_entry", {"attempt": int(attempt_counts[active_spot.id])})
	spot_changed.emit(active_spot)

func _update_feature_flow() -> void:
	if active_spot == null:
		return
	var player_course_position := _player.global_position
	for feature_id: StringName in active_spot.feature_ids:
		var spec: Dictionary = _features.get(feature_id, {})
		if spec.is_empty():
			continue
		var feature_position := feature_course_position(spec)
		var distance := Vector2(player_course_position.x - feature_position.x, player_course_position.z - feature_position.z).length()
		if distance <= FEATURE_APPROACH_DISTANCE and not _approached.has(feature_id):
			_approached[feature_id] = true
			record_event(&"feature_approach", {"feature_id": feature_id, "route": spec.route})
		if _approached.has(feature_id) and not _completed_in_attempt.has(feature_id) and player_course_position.z < feature_position.z - FEATURE_COMPLETE_DOWNHILL_DISTANCE:
			_completed_in_attempt[feature_id] = true
			_route_features.append(feature_id)
			record_event(&"feature_complete", {"feature_id": feature_id, "route": spec.route})

func _complete_route() -> void:
	var route: StringName = &"safe"
	for feature_id: StringName in _route_features:
		var feature: Dictionary = _features.get(feature_id, {})
		var candidate := StringName(feature.get("route", &"safe"))
		if _route_rank(candidate) > _route_rank(route):
			route = candidate
	record_event(&"route_complete", {"route": route, "feature_ids": _route_features.duplicate()})

func _on_player_telemetry(data: Dictionary) -> void:
	var flick := data.get("flick", {}) as Dictionary
	var state_name := str(data.get("state", ""))
	if state_name == "AIR" or state_name == "Air" or str(flick.get("kind", "NONE")) != "NONE":
		_last_rotation_degrees = maxf(
			_last_rotation_degrees,
			maxf(float(flick.get("yaw_degrees", 0)), maxf(float(flick.get("flip_degrees", 0)), float(flick.get("cork_degrees", 0))))
		)
	var grab_active := bool(flick.get("grab_qualified", false)) or str(flick.get("live_grab", "")) != ""
	if grab_active and not _last_grab_active:
		record_event(&"grab", {"active": true})
	_last_grab_active = grab_active

func _on_state_changed(state_name: String) -> void:
	if state_name == "Air" and _last_state != "Air":
		_last_rotation_degrees = 0.0
		_last_grab_active = false
	if state_name == "Grind":
		_last_rail_feature_id = _active_rail_feature_id()
		record_event(&"rail_capture", {"feature_id": _last_rail_feature_id, "captured": true})
	if state_name == "Bail":
		record_event(&"bail", {"source": "rail" if _last_state == "Grind" else _last_state.to_lower()})
	_last_state = state_name

func _on_rail_finished(feature_id: StringName, outcome: StringName) -> void:
	# The controller owns the rail outcome explicitly: a teleport/recovery
	# cancels the attempt and must not emit a successful rail result.
	if outcome == &"cancelled":
		record_event(&"rail_cancelled", {"feature_id": feature_id, "captured": true})
		return
	var failed := outcome == &"failed"
	record_event(&"rail_exit", {"feature_id": feature_id, "captured": true, "failed": failed})
	record_event(&"rail_result", {"feature_id": feature_id, "success": not failed})

func _on_landed(result: Dictionary) -> void:
	record_event(&"air_rotation", {"degrees": _last_rotation_degrees})
	record_event(&"landing", result)

func _on_crashed() -> void:
	# state_changed carries the authoritative source state and records the bail.
	pass

func _on_score_changed(score_snapshot: Dictionary) -> void:
	record_event(&"score", {"total_score": int(score_snapshot.get("total_score", 0))})

func _on_run_finished(score_snapshot: Dictionary) -> void:
	_complete_route()
	record_event(&"run_complete", {"total_score": int(score_snapshot.get("total_score", 0))})

func _on_marker_changed(position: Vector3) -> void:
	record_event(&"marker_save", {"position": position})

func _on_respawn_applied(value: Transform3D) -> void:
	var returned_to_marker := SessionManager.has_marker and value.origin.distance_to(SessionManager.marker.origin) < 1.0
	record_event(&"marker_return" if returned_to_marker else &"restart", {"position": value.origin})
	_update_active_spot(true)

func _on_challenge_completed(challenge: ParkChallengeSpec) -> void:
	record_event(&"challenge_complete", {"challenge_id": challenge.id})
	challenge_updated.emit(challenge_tracker.snapshot())

func _active_rail_feature_id() -> StringName:
	if _player == null or _player.active_rail == null:
		return &""
	return StringName(_player.active_rail.get_meta("feature_id", StringName(_player.active_rail.name.to_snake_case())))

static func feature_course_position(spec: Dictionary) -> Vector3:
	if StringName(spec.get("kind", &"")) == &"rail":
		var points := spec.get("points", []) as Array
		if not points.is_empty():
			var encoded := points[0] as Vector3
			return Vector3(encoded.x, 0.0, encoded.y)
	return Vector3(float(spec.get("x", 0.0)), 0.0, float(spec.get("z", 0.0)))

func _route_rank(route: StringName) -> int:
	match route:
		&"expert": return 2
		&"intermediate": return 1
	return 0

func _disconnect_player() -> void:
	if _player == null:
		return
	if _player.state_changed.is_connected(_on_state_changed): _player.state_changed.disconnect(_on_state_changed)
	if _player.rail_finished.is_connected(_on_rail_finished): _player.rail_finished.disconnect(_on_rail_finished)
	if _player.telemetry_updated.is_connected(_on_player_telemetry): _player.telemetry_updated.disconnect(_on_player_telemetry)
	if _player.landed.is_connected(_on_landed): _player.landed.disconnect(_on_landed)
	if _player.crashed.is_connected(_on_crashed): _player.crashed.disconnect(_on_crashed)
	if _player.respawn_applied.is_connected(_on_respawn_applied): _player.respawn_applied.disconnect(_on_respawn_applied)
	if _player.scoring != null and _player.scoring.score_changed.is_connected(_on_score_changed): _player.scoring.score_changed.disconnect(_on_score_changed)
	if _player.scoring != null and _player.scoring.run_finished.is_connected(_on_run_finished): _player.scoring.run_finished.disconnect(_on_run_finished)
	_player = null
