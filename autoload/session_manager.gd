extends Node

const PROGRESS_PATH := "user://progress.cfg"

signal marker_changed(position: Vector3)
signal respawn_requested(transform: Transform3D, reason: StringName)

const RESPAWN_SESSION := &"session"
const RESPAWN_SUMMIT_RESTART := &"summit_restart"
const RESPAWN_COURSE_RECOVERY := &"course_recovery"

var default_spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 98.0, 138.0))
var marker := Transform3D.IDENTITY
var has_marker := false
var best_score := 0

func _ready() -> void:
	var progress := ConfigFile.new()
	if progress.load(PROGRESS_PATH) == OK:
		best_score = maxi(0, int(progress.get_value("records", "best_score", 0)))

func set_default_spawn(value: Transform3D) -> void:
	default_spawn = value

func set_marker(value: Transform3D) -> void:
	marker = value
	has_marker = true
	marker_changed.emit(value.origin)

func request_respawn() -> void:
	respawn_requested.emit(marker if has_marker else default_spawn, RESPAWN_SESSION)

func request_respawn_to(value: Transform3D, reason: StringName = RESPAWN_COURSE_RECOVERY) -> void:
	respawn_requested.emit(value, reason)

func request_summit_restart() -> void:
	respawn_requested.emit(default_spawn, RESPAWN_SUMMIT_RESTART)

func clear_marker() -> void:
	has_marker = false

func submit_score(score: int, progress_path: String = PROGRESS_PATH) -> bool:
	if score <= best_score:
		return false
	var progress := ConfigFile.new()
	var load_error := progress.load(progress_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load personal best: %s" % error_string(load_error))
		return false
	progress.set_value("records", "best_score", score)
	var error := progress.save(progress_path)
	if error != OK:
		push_warning("Could not save personal best: %s" % error_string(error))
		return false
	best_score = score
	return true
