class_name ParkContentTracker
extends Node

signal spot_changed(spot: ParkSpotSpec)
signal challenge_updated(snapshot: Dictionary)
signal content_event_recorded(event: Dictionary)

const MAX_TRACE_EVENTS := 256

var telemetry_enabled := OS.is_debug_build() or OS.get_cmdline_user_args().has("--content-trace")
var challenge_tracker := ParkChallengeTracker.new()
var active_spot: ParkSpotSpec
var attempt_counts: Dictionary = {}
var trace_events: Array[Dictionary] = []
var spot_diagnostics: Dictionary = {}

var _profile: ParkCourseProfile
var _player: SkierController
var _camera: SkiCameraController
var _spots: Array[ParkSpotSpec] = []
var _features: Dictionary = {}
var _completed_in_attempt: Dictionary = {}
var _route_features: Array[StringName] = []
var _attempt_start_score := 0
var _last_state := ""
var _last_rail_feature_id: StringName
var _last_rotation_degrees := 0.0
var _last_grab_active := false
var _last_camera_fallback_count := 0
var _latest_player_telemetry: Dictionary = {}
var _camera_fallback_streak_active := false
var _camera_fallback_streak_spot: StringName
var _camera_fallback_streak_state := ""
var _pending_landing_feedback: Dictionary = {}
var _pending_landing_spot_id: StringName

func _ready() -> void:
	challenge_tracker.name = "ChallengeTracker"
	add_child(challenge_tracker)
	challenge_tracker.challenge_completed.connect(_on_challenge_completed)
	challenge_tracker.attempt_changed.connect(func(snapshot: Dictionary) -> void: challenge_updated.emit(snapshot))

func configure(
	profile: ParkCourseProfile,
	player: SkierController = null,
	camera: SkiCameraController = null
) -> void:
	_disconnect_player()
	_profile = profile
	_player = player
	_camera = camera
	_spots = profile.spot_specs() if profile != null else []
	_features.clear()
	spot_diagnostics.clear()
	_latest_player_telemetry.clear()
	_camera_fallback_streak_active = false
	_camera_fallback_streak_spot = &""
	_camera_fallback_streak_state = ""
	_pending_landing_feedback.clear()
	_pending_landing_spot_id = &""
	_last_camera_fallback_count = int(
		_camera.content_diagnostic_snapshot().get("camera_fallback_count", 0)
	) if _camera != null else 0
	if profile != null:
		for spec: Dictionary in profile.feature_specs():
			_features[StringName(spec.get("feature_id", &""))] = spec
		challenge_tracker.configure(profile.challenge_specs())
	if _player != null:
		_player.state_changed.connect(_on_state_changed)
		_player.rail_finished.connect(_on_rail_finished)
		_player.feature_used.connect(_on_feature_used)
		_player.telemetry_updated.connect(_on_player_telemetry)
		_player.landed.connect(_on_landed)
		if _player.trick != null:
			_player.trick.trick_landed.connect(_on_trick_landed)
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
	if telemetry_enabled and _camera != null:
		observe_camera_snapshot(_camera.content_diagnostic_snapshot(), _latest_player_telemetry)

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
		"spot_diagnostics": spot_diagnostics.duplicate(true) if telemetry_enabled else {},
		"challenge": challenge_tracker.snapshot(),
		"trace_events": trace_events.duplicate(true) if telemetry_enabled else [],
	}

## Aggregates cumulative camera diagnostics by the active content spot. This
## accepts snapshots rather than reaching into camera internals, keeping the
## content tracker deterministic and directly testable.
func observe_camera_snapshot(camera_snapshot: Dictionary, player_snapshot: Dictionary = {}) -> void:
	if not telemetry_enabled or active_spot == null:
		return
	var diagnostics := _active_spot_diagnostics()
	var carve_offset: Variant = camera_snapshot.get("carve_look_ahead_offset", Vector3.ZERO)
	var carve_offset_length: float = (carve_offset as Vector3).length() if carve_offset is Vector3 else 0.0
	diagnostics["max_carve_look_ahead_m"] = maxf(
		float(diagnostics.get("max_carve_look_ahead_m", 0.0)),
		carve_offset_length
	)
	var current_count := maxi(0, int(camera_snapshot.get("camera_fallback_count", 0)))
	if current_count < _last_camera_fallback_count:
		# Camera reset/retarget starts a new cumulative counter. Treat the current
		# value as the new baseline rather than attributing a negative delta.
		_last_camera_fallback_count = current_count
		_camera_fallback_streak_active = false
		return
	var fallback_delta := current_count - _last_camera_fallback_count
	if fallback_delta <= 0:
		_camera_fallback_streak_active = false
		return
	_last_camera_fallback_count = current_count
	var camera_state := str(camera_snapshot.get("state", "UNKNOWN"))
	var by_state := diagnostics.get("camera_fallbacks_by_state", {}) as Dictionary
	by_state[camera_state] = int(by_state.get(camera_state, 0)) + fallback_delta
	diagnostics["camera_fallbacks_by_state"] = by_state
	diagnostics["camera_fallback_count"] = int(
		diagnostics.get("camera_fallback_count", 0)
	) + fallback_delta
	var context := {
		"count": fallback_delta,
		"total_count": current_count,
		"camera_state": camera_state,
		"player_state": str(player_snapshot.get("state", "UNKNOWN")),
		"speed_mps": float(player_snapshot.get("speed_mps", 0.0)),
		"target_distance_m": float(camera_snapshot.get("target_distance", 0.0)),
		"composition_recovery_active": bool(camera_snapshot.get("composition_recovery_active", false)),
		"camera_occluded": bool(camera_snapshot.get("camera_occluded", false)),
		"foreground_occlusion_fraction": float(camera_snapshot.get("foreground_occlusion_fraction", 0.0)),
		"carve_look_ahead_m": carve_offset_length,
	}
	diagnostics["last_camera_fallback"] = context.duplicate(true)
	var starts_episode := not _camera_fallback_streak_active \
		or _camera_fallback_streak_spot != active_spot.id \
		or _camera_fallback_streak_state != camera_state
	_camera_fallback_streak_active = true
	_camera_fallback_streak_spot = active_spot.id
	_camera_fallback_streak_state = camera_state
	if starts_episode:
		diagnostics["camera_fallback_event_count"] = int(
			diagnostics.get("camera_fallback_event_count", 0)
		) + 1
		record_event(&"camera_fallback", context)

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

func _on_feature_used(feature_id: StringName, _feature_kind: StringName, use_kind: StringName) -> void:
	if _player == null or active_spot == null or feature_id == &"":
		return
	if feature_id not in active_spot.feature_ids:
		return
	if _completed_in_attempt.has(feature_id):
		return
	# Authoritative completion: the controller only emits use events for real
	# ride/takeoff/rail/contact interactions, so proximity passes never credit.
	_completed_in_attempt[feature_id] = true
	_route_features.append(feature_id)
	var spec: Dictionary = _features.get(feature_id, {})
	record_event(&"feature_complete", {
		"feature_id": feature_id,
		"route": spec.get("route", &"safe"),
		"use": use_kind,
	})

func _complete_route() -> void:
	var route: StringName = &"safe"
	for feature_id: StringName in _route_features:
		var feature: Dictionary = _features.get(feature_id, {})
		var candidate := StringName(feature.get("route", &"safe"))
		if _route_rank(candidate) > _route_rank(route):
			route = candidate
	record_event(&"route_complete", {"route": route, "feature_ids": _route_features.duplicate()})

func _on_player_telemetry(data: Dictionary) -> void:
	_latest_player_telemetry = {
		"state": str(data.get("state", "UNKNOWN")),
		"speed_mps": float(data.get("speed_mps", 0.0)),
	}
	_finalize_pending_landing_feedback(data)
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
	if not telemetry_enabled:
		return
	var feedback := _landing_feedback(result)
	var diagnostics := _active_spot_diagnostics()
	diagnostics["landing_count"] = int(diagnostics.get("landing_count", 0)) + 1
	var outcomes := diagnostics.get("landing_outcomes", {}) as Dictionary
	var outcome_name := str(feedback.get("outcome_name", "UNKNOWN"))
	outcomes[outcome_name] = int(outcomes.get(outcome_name, 0)) + 1
	diagnostics["landing_outcomes"] = outcomes
	diagnostics["last_landing"] = feedback.duplicate(true)
	if _player != null:
		feedback["speed_before_mps"] = _player.velocity.length()
		diagnostics["last_landing"] = feedback.duplicate(true)
		_pending_landing_feedback = feedback.duplicate(true)
		_pending_landing_spot_id = active_spot.id if active_spot != null else &""
	else:
		record_event(&"landing_feedback", feedback)

func _on_trick_landed(text: String, points: int, quality: float, outcome: int) -> void:
	if not telemetry_enabled:
		return
	var rotation := {}
	if _player != null and _player.trick != null:
		rotation = _player.trick.rotation_snapshot()
	var kind := int(rotation.get("kind", TrickCommand.Kind.NONE))
	var kind_names := TrickCommand.Kind.keys()
	var feedback := {
		"name": text,
		"points": points,
		"quality": quality,
		"outcome": outcome,
		"outcome_name": _landing_outcome_name(outcome),
		"rotation_kind": kind,
		"rotation_kind_name": kind_names[clampi(kind, 0, kind_names.size() - 1)],
		"rotation_target_degrees": int(rotation.get("target_degrees", 0)),
		"rotation_residual_degrees": float(rotation.get("residual_degrees", 0.0)),
		"rotation_accumulated": rotation.get("accumulated_rotation", Vector3.ZERO),
	}
	var diagnostics := _active_spot_diagnostics()
	diagnostics["trick_landing_count"] = int(
		diagnostics.get("trick_landing_count", 0)
	) + 1
	diagnostics["last_trick"] = feedback.duplicate(true)
	record_event(&"trick_feedback", feedback)

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

func _route_rank(route: StringName) -> int:
	match route:
		&"expert": return 2
		&"intermediate": return 1
	return 0

func _active_spot_diagnostics() -> Dictionary:
	if active_spot == null:
		return {}
	if not spot_diagnostics.has(active_spot.id):
		spot_diagnostics[active_spot.id] = {
			"camera_fallback_count": 0,
			"camera_fallback_event_count": 0,
			"camera_fallbacks_by_state": {},
			"max_carve_look_ahead_m": 0.0,
			"landing_count": 0,
			"landing_outcomes": {},
			"trick_landing_count": 0,
			"last_camera_fallback": {},
			"last_landing": {},
			"last_trick": {},
		}
	return spot_diagnostics[active_spot.id] as Dictionary

func _landing_feedback(result: Dictionary) -> Dictionary:
	var outcome := int(result.get("outcome", LandingSolver.Outcome.CLEAN))
	return {
		"outcome": outcome,
		"outcome_name": _landing_outcome_name(outcome),
		"score": float(result.get("score", 0.0)),
		"impact_speed_mps": float(result.get("impact", 0.0)),
		"impact_severity": float(result.get("impact_severity", 0.0)),
		"balance_error": float(result.get("balance_error", 0.0)),
		"ski_alignment_error": float(result.get("ski_alignment_error", 0.0)),
		"body_roll_error": float(result.get("body_roll_error", 0.0)),
		"body_pitch_error": float(result.get("body_pitch_error", 0.0)),
		"rotation_residual_degrees": float(result.get("rotation_residual_degrees", 0.0)),
		"rotation_quality": float(result.get("rotation_quality", 1.0)),
		"rotation_orientation_error_degrees": float(result.get("rotation_orientation_error_degrees", 0.0)),
	}

func _finalize_pending_landing_feedback(data: Dictionary) -> void:
	if _pending_landing_feedback.is_empty() or str(data.get("state", "")) != "GROUND":
		return
	var feedback := _pending_landing_feedback.duplicate(true)
	var speed_before := float(feedback.get("speed_before_mps", 0.0))
	var speed_after := float(data.get("speed_mps", 0.0))
	feedback["speed_after_mps"] = speed_after
	feedback["speed_loss_mps"] = maxf(speed_before - speed_after, 0.0)
	feedback["speed_retention"] = speed_after / maxf(speed_before, 0.01)
	var diagnostics := spot_diagnostics.get(_pending_landing_spot_id, {}) as Dictionary
	if not diagnostics.is_empty():
		diagnostics["last_landing"] = feedback.duplicate(true)
	record_event(&"landing_feedback", feedback)
	_pending_landing_feedback.clear()
	_pending_landing_spot_id = &""

func _landing_outcome_name(outcome: int) -> String:
	var outcome_names := LandingSolver.Outcome.keys()
	return outcome_names[clampi(outcome, 0, outcome_names.size() - 1)]

func _disconnect_player() -> void:
	if _player == null:
		_camera = null
		return
	if _player.state_changed.is_connected(_on_state_changed): _player.state_changed.disconnect(_on_state_changed)
	if _player.rail_finished.is_connected(_on_rail_finished): _player.rail_finished.disconnect(_on_rail_finished)
	if _player.feature_used.is_connected(_on_feature_used): _player.feature_used.disconnect(_on_feature_used)
	if _player.telemetry_updated.is_connected(_on_player_telemetry): _player.telemetry_updated.disconnect(_on_player_telemetry)
	if _player.landed.is_connected(_on_landed): _player.landed.disconnect(_on_landed)
	if _player.trick != null and _player.trick.trick_landed.is_connected(_on_trick_landed):
		_player.trick.trick_landed.disconnect(_on_trick_landed)
	if _player.crashed.is_connected(_on_crashed): _player.crashed.disconnect(_on_crashed)
	if _player.respawn_applied.is_connected(_on_respawn_applied): _player.respawn_applied.disconnect(_on_respawn_applied)
	if _player.scoring != null and _player.scoring.score_changed.is_connected(_on_score_changed): _player.scoring.score_changed.disconnect(_on_score_changed)
	if _player.scoring != null and _player.scoring.run_finished.is_connected(_on_run_finished): _player.scoring.run_finished.disconnect(_on_run_finished)
	_player = null
	_camera = null
