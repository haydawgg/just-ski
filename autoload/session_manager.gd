extends Node

const PROGRESS_PATH := "user://progress.cfg"

signal marker_changed(position: Vector3)
signal respawn_requested(transform: Transform3D, reason: StringName)

enum ScoreResult { NOT_RECORD, SAVED, LOAD_FAILED, SAVE_FAILED }

const RESPAWN_SESSION := &"session"
const RESPAWN_NEW_RUN_MARKER := &"new_run_marker"
const RESPAWN_SUMMIT_RESTART := &"summit_restart"
const RESPAWN_COURSE_RECOVERY := &"course_recovery"

var default_spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 98.0, 138.0))
var marker := Transform3D.IDENTITY
var has_marker := false
var best_score := 0
var respawn_serial := 0

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
	_emit_respawn(marker if has_marker else default_spawn, RESPAWN_SESSION)

func request_new_run_from_marker() -> void:
	if not has_marker:
		return
	_emit_respawn(marker, RESPAWN_NEW_RUN_MARKER)

func request_respawn_to(value: Transform3D, reason: StringName = RESPAWN_COURSE_RECOVERY) -> void:
	_emit_respawn(value, reason)

func request_summit_restart() -> void:
	_emit_respawn(default_spawn, RESPAWN_SUMMIT_RESTART)

func clear_marker() -> void:
	has_marker = false

func _emit_respawn(transform: Transform3D, reason: StringName) -> void:
	respawn_serial += 1
	respawn_requested.emit(transform, reason)

func submit_score(score: int, progress_path: String = PROGRESS_PATH) -> ScoreResult:
	# Comparison uses the in-memory best, which is the most recent known value
	# even when the stored file is unreadable.
	if score <= best_score:
		return ScoreResult.NOT_RECORD
	var progress := ConfigFile.new()
	var load_error := progress.load(progress_path)
	var recovered := false
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		# The records section is unreadable: back the corrupt file up and
		# rebuild it so one bad file cannot block every future record.
		push_warning("Could not load personal best (%s); rebuilding records" % error_string(load_error))
		_backup_corrupt_progress(progress_path)
		recovered = true
	progress.set_value("records", "best_score", score)
	var error := progress.save(progress_path)
	if error != OK:
		push_warning("Could not save personal best: %s" % error_string(error))
		return ScoreResult.SAVE_FAILED
	best_score = score
	return ScoreResult.LOAD_FAILED if recovered else ScoreResult.SAVED

func _backup_corrupt_progress(progress_path: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var backup := "%s.corrupt-%s" % [progress_path, stamp]
	var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(progress_path), ProjectSettings.globalize_path(backup))
	if error != OK:
		push_warning("Could not back up corrupt progress file: %s" % error_string(error))
