extends Node

const PROGRESS_PATH := "user://progress.cfg"

signal marker_changed(position: Vector3)
signal respawn_requested(transform: Transform3D)

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
	respawn_requested.emit(marker if has_marker else default_spawn)

func clear_marker() -> void:
	has_marker = false

func submit_score(score: int) -> bool:
	if score <= best_score:
		return false
	best_score = score
	var progress := ConfigFile.new()
	progress.set_value("records", "best_score", best_score)
	var error := progress.save(PROGRESS_PATH)
	if error != OK:
		push_warning("Could not save personal best: %s" % error_string(error))
	return true
