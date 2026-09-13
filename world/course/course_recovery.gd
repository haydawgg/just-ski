class_name CourseRecovery
extends Node

## Course recovery is an explicit lifecycle rather than a one-frame teleport.
## Keep the reason on the signal so crash/replay diagnostics can distinguish a
## valid out-of-bounds recovery from an invalid transform.
signal recovery_started(reason: String)
signal recovery_respawned(reason: String, spawn_transform: Transform3D)
signal recovery_completed(reason: String, spawn_transform: Transform3D)
signal recovery_cancelled(reason: String)

enum RecoveryReason { OUT_OF_BOUNDS, INVALID_POSITION }

@export var minimum_y := -24.0
@export var minimum_z := -225.0
@export var maximum_z := ParkLayout.DEFAULT_SPAWN_WORLD_Z + 10.0
@export var maximum_lateral_distance := 72.0
@export var recovery_delay := 0.45
@export var fade_out_duration := 0.12
@export var fade_in_duration := 0.18

var target: CharacterBody3D
var outside_time := 0.0
var recovering := false
var recovery_elapsed := 0.0
var respawn_issued := false
var recovery_count := 0
var last_recovery_reason := ""
var last_respawn_transform := Transform3D.IDENTITY
var course_profile: ParkCourseProfile

var recovery_in_progress: bool:
	get:
		return recovering

func _ready() -> void:
	SessionManager.respawn_requested.connect(_on_session_respawn_requested)

func _exit_tree() -> void:
	if SessionManager.respawn_requested.is_connected(_on_session_respawn_requested):
		SessionManager.respawn_requested.disconnect(_on_session_respawn_requested)

func _on_session_respawn_requested(_value: Transform3D, reason: StringName) -> void:
	# Recovery is one atomic transition. A foreign respawn (pause menu, hotkey
	# fallback, results flow) takes ownership and must cancel the pending
	# recovery respawn so exactly one teleport commits.
	if recovering and reason != SessionManager.RESPAWN_COURSE_RECOVERY:
		cancel()

func set_target(value: CharacterBody3D) -> void:
	target = value
	outside_time = 0.0
	recovering = false
	recovery_elapsed = 0.0
	respawn_issued = false
	if target != null and target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", false)

func cancel() -> void:
	if not recovering:
		return
	recovering = false
	recovery_elapsed = 0.0
	respawn_issued = true
	if target != null and target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", false)
	recovery_cancelled.emit(last_recovery_reason)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	if recovering:
		recovery_elapsed += delta
		if not respawn_issued and recovery_elapsed >= maxf(fade_out_duration, 0.0):
			respawn_issued = true
			last_respawn_transform = _recovery_spawn_transform()
			SessionManager.request_respawn_to(last_respawn_transform)
			recovery_respawned.emit(last_recovery_reason, last_respawn_transform)
		if respawn_issued and recovery_elapsed >= maxf(fade_out_duration, 0.0) + maxf(fade_in_duration, 0.0):
			_finish_recovery()
		return
	var position := target.global_position
	var invalid_transform := not position.is_finite()
	var invalid_bounds := (
		position.y < minimum_y
		or position.z < minimum_z
		or position.z > maximum_z
		or absf(position.x) > maximum_lateral_distance
	)
	if not invalid_transform and not invalid_bounds:
		outside_time = 0.0
		return
	outside_time += delta
	var required_delay := 0.0 if invalid_transform else maxf(recovery_delay, 0.0)
	if outside_time < required_delay:
		return
	recovering = true
	recovery_elapsed = 0.0
	respawn_issued = false
	recovery_count += 1
	last_recovery_reason = RecoveryReason.keys()[RecoveryReason.INVALID_POSITION if invalid_transform else RecoveryReason.OUT_OF_BOUNDS]
	if target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", true)
	recovery_started.emit(last_recovery_reason)
	outside_time = 0.0

func _finish_recovery() -> void:
	if not recovering:
		return
	recovering = false
	recovery_elapsed = 0.0
	respawn_issued = false
	if target != null and target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", false)
	recovery_completed.emit(last_recovery_reason, last_respawn_transform)

func _recovery_spawn_transform() -> Transform3D:
	if SessionManager.has_marker:
		return SessionManager.marker
	if course_profile == null or target == null:
		return SessionManager.default_spawn
	var player_z := target.global_position.z
	var best := SessionManager.default_spawn
	var best_delta := INF
	for spot: ParkSpotSpec in course_profile.spot_specs():
		var marker := spot.recommended_marker_position
		if marker.z < player_z:
			continue
		var origin := ParkLayout.surface_hover(marker.x, marker.z, ParkLayout.SPAWN_HOVER)
		var delta_z := marker.z - player_z
		if delta_z < best_delta:
			best_delta = delta_z
			best = Transform3D(ParkLayout.downhill_basis(), origin)
	return best
