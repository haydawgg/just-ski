class_name TrickPresentationClassifier
extends RefCounted

const CORK_WEIGHT_THRESHOLD := 0.22

func classify(axis_local: Vector3, fallback_kind: int = TrickCommand.Kind.NONE) -> int:
	if axis_local.length_squared() <= 0.0001:
		return fallback_kind
	var weights := axis_weights(axis_local)
	if weights.z >= CORK_WEIGHT_THRESHOLD and weights.y > 0.08:
		return TrickCommand.Kind.CORK_LEFT if axis_local.y < 0.0 else TrickCommand.Kind.CORK_RIGHT
	if weights.x >= weights.y:
		return TrickCommand.Kind.FRONTFLIP if axis_local.x > 0.0 else TrickCommand.Kind.BACKFLIP
	return TrickCommand.Kind.SPIN_LEFT if axis_local.y < 0.0 else TrickCommand.Kind.SPIN_RIGHT

func axis_weights(axis_local: Vector3) -> Vector3:
	var axis := axis_local.normalized() if axis_local.length_squared() > 0.0001 else Vector3.ZERO
	var absolute := Vector3(absf(axis.x), absf(axis.y), absf(axis.z))
	var total := absolute.x + absolute.y + absolute.z
	return absolute / total if total > 0.0001 else Vector3.ZERO

func primary_progress_radians(axis_local: Vector3, accumulated_rotation: Vector3, fallback_kind: int) -> float:
	var axis := axis_local.normalized() if axis_local.length_squared() > 0.0001 else _fallback_axis(fallback_kind)
	return accumulated_rotation.dot(axis)

func target_degrees(axis_local: Vector3, accumulated_rotation: Vector3, fallback_kind: int) -> int:
	var kind := classify(axis_local, fallback_kind)
	var step := 360.0 if kind in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP] else 180.0
	var underrotation := 45.0 if step >= 360.0 else 25.0
	var actual := rad_to_deg(absf(primary_progress_radians(axis_local, accumulated_rotation, fallback_kind)))
	if actual + underrotation < step:
		return 0
	return maxi(0, int(step) * int(floor((actual + underrotation) / step)))

func residual_degrees(axis_local: Vector3, accumulated_rotation: Vector3, fallback_kind: int) -> float:
	var target := target_degrees(axis_local, accumulated_rotation, fallback_kind)
	if target <= 0:
		return 0.0
	return rad_to_deg(absf(primary_progress_radians(axis_local, accumulated_rotation, fallback_kind))) - float(target)

func residual_vector(axis_local: Vector3, accumulated_rotation: Vector3, fallback_kind: int) -> Vector3:
	var target := target_degrees(axis_local, accumulated_rotation, fallback_kind)
	if target <= 0:
		return Vector3.ZERO
	var axis := axis_local.normalized() if axis_local.length_squared() > 0.0001 else _fallback_axis(fallback_kind)
	var progress_sign := signf(accumulated_rotation.dot(axis))
	return axis * deg_to_rad(residual_degrees(axis_local, accumulated_rotation, fallback_kind)) * progress_sign

func _fallback_axis(kind: int) -> Vector3:
	match kind:
		TrickCommand.Kind.SPIN_LEFT: return Vector3(0.0, -1.0, 0.0)
		TrickCommand.Kind.SPIN_RIGHT: return Vector3(0.0, 1.0, 0.0)
		TrickCommand.Kind.FRONTFLIP: return Vector3(1.0, 0.0, 0.0)
		TrickCommand.Kind.BACKFLIP: return Vector3(-1.0, 0.0, 0.0)
		TrickCommand.Kind.CORK_LEFT: return Vector3(0.0, -1.0, -1.0).normalized()
		TrickCommand.Kind.CORK_RIGHT: return Vector3(0.0, 1.0, 1.0).normalized()
	return Vector3.ZERO
