extends Node

signal marker_changed(position: Vector3)
signal respawn_requested(transform: Transform3D)

var default_spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 21.5, 75.0))
var marker := Transform3D.IDENTITY
var has_marker := false

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
