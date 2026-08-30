class_name SkiContactPresentation
extends RefCounted

## Presentation snapshot of the authoritative ski contact solver.
##
## This module intentionally does not query physics. VFX, tracks, and other
## presentation adapters consume the same per-ski contact data so their
## origins and surface decisions cannot drift apart.

enum Side { LEFT, RIGHT }
enum SurfaceClass { SNOW, FEATURE, METAL, UNKNOWN }

var surface_class := SurfaceClass.UNKNOWN
var left_valid := false
var right_valid := false
var left_confidence := 0.0
var right_confidence := 0.0
var left_position := Vector3.ZERO
var right_position := Vector3.ZERO
var left_normal := Vector3.UP
var right_normal := Vector3.UP

func capture(contact: SkiContactSolver) -> void:
	if contact == null:
		_reset()
		return
	surface_class = clampi(int(contact.surface_class), SurfaceClass.SNOW, SurfaceClass.UNKNOWN)
	left_confidence = clampf(contact.left_contact_confidence, 0.0, 1.0)
	right_confidence = clampf(contact.right_contact_confidence, 0.0, 1.0)
	left_valid = contact.left_grounded and left_confidence > 0.2
	right_valid = contact.right_grounded and right_confidence > 0.2
	left_position = contact.left_hit_position
	right_position = contact.right_hit_position
	left_normal = _safe_normal(contact.left_normal)
	right_normal = _safe_normal(contact.right_normal)

func allows_snow_effects() -> bool:
	return surface_class == SurfaceClass.SNOW and (left_valid or right_valid)

func valid(side: Side) -> bool:
	return left_valid if side == Side.LEFT else right_valid

func position(side: Side) -> Vector3:
	return left_position if side == Side.LEFT else right_position

func normal(side: Side) -> Vector3:
	return left_normal if side == Side.LEFT else right_normal

func _reset() -> void:
	surface_class = SurfaceClass.UNKNOWN
	left_valid = false
	right_valid = false
	left_confidence = 0.0
	right_confidence = 0.0
	left_position = Vector3.ZERO
	right_position = Vector3.ZERO
	left_normal = Vector3.UP
	right_normal = Vector3.UP

func _safe_normal(value: Vector3) -> Vector3:
	return value.normalized() if value.length_squared() > 0.001 else Vector3.UP
