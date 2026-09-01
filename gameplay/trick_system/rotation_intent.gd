class_name RotationIntent
extends RefCounted

var committed := false
var impulse_local := Vector3.ZERO
var axis_local := Vector3.ZERO
var axis_weights := Vector3.ZERO
var magnitude := 0.0
var setup_quality := 0.0
var presentation_kind := TrickCommand.Kind.NONE

func configure(value: Vector3, quality: float, kind: int) -> RotationIntent:
	impulse_local = value
	magnitude = value.length()
	axis_local = value.normalized() if magnitude > 0.0001 else Vector3.ZERO
	axis_weights = _normalized_weights(axis_local)
	setup_quality = clampf(quality, 0.0, 1.0)
	presentation_kind = kind
	committed = magnitude > 0.0001
	return self

func snapshot() -> Dictionary:
	return {
		"committed": committed,
		"impulse_local": impulse_local,
		"axis_local": axis_local,
		"axis_weights": axis_weights,
		"magnitude": magnitude,
		"setup_quality": setup_quality,
		"presentation_kind": presentation_kind,
	}

func _normalized_weights(axis: Vector3) -> Vector3:
	var absolute := Vector3(absf(axis.x), absf(axis.y), absf(axis.z))
	var total := absolute.x + absolute.y + absolute.z
	return absolute / total if total > 0.0001 else Vector3.ZERO
