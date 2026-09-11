class_name EquipmentFeatureCollisionSolver
extends RefCounted

## Sweeps the visible ski envelopes against solid park features. Snow-plane
## contact stays owned by the per-ski contact and suspension system; pole
## sweeps may additionally scan terrain, but only steep faces can bail (gated
## by the caller landing window and the crash evaluator normal check).

const FEATURE_MASK := 4
const SKI_RADIUS := 0.075
const POLE_RADIUS := 0.05
const CONTACT_MARGIN := 0.025

var _shape := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()

func sweep(
	space: PhysicsDirectSpaceState3D,
	segments: Dictionary,
	motion: Vector3,
	exclude: Array[RID]
) -> Dictionary:
	var best := {"hit": false, "safe_fraction": 1.0}
	if space == null or motion.length_squared() <= 0.000001:
		return best
	for side: StringName in [&"left", &"right"]:
		var segment := segments.get(side, {}) as Dictionary
		var nose := segment.get("nose", Vector3.ZERO) as Vector3
		var tail := segment.get("tail", Vector3.ZERO) as Vector3
		var axis := nose - tail
		if axis.length() <= 0.2:
			continue
		var contact := _cast_capsule(space, nose, tail, SKI_RADIUS, motion, exclude, FEATURE_MASK)
		if not bool(contact.get("hit", false)):
			continue
		if float(contact.get("safe_fraction", 1.0)) >= float(best.get("safe_fraction", 1.0)):
			continue
		contact["side"] = side
		best = contact
	return best

## Sweeps pole shafts (grip-excluded segments supplied by the rig adapter)
## against solid park features. Same crash-report shape as sweep(); callers
## decide whether a hit bails or only retracts presentation.
func sweep_poles(
	space: PhysicsDirectSpaceState3D,
	segments: Dictionary,
	motion: Vector3,
	exclude: Array[RID],
	mask: int = FEATURE_MASK
) -> Dictionary:
	var best := {"hit": false, "safe_fraction": 1.0}
	if space == null or motion.length_squared() <= 0.000001:
		return best
	for side: StringName in [&"left", &"right"]:
		var segment := segments.get(side, {}) as Dictionary
		var start := segment.get("start", Vector3.ZERO) as Vector3
		var end := segment.get("end", Vector3.ZERO) as Vector3
		if (end - start).length() <= 0.05:
			continue
		var contact := _cast_capsule(space, start, end, POLE_RADIUS, motion, exclude, mask)
		if not bool(contact.get("hit", false)):
			continue
		if float(contact.get("safe_fraction", 1.0)) >= float(best.get("safe_fraction", 1.0)):
			continue
		contact["side"] = side
		best = contact
	return best

func _cast_capsule(
	space: PhysicsDirectSpaceState3D,
	a: Vector3,
	b: Vector3,
	radius: float,
	motion: Vector3,
	exclude: Array[RID],
	mask: int
) -> Dictionary:
	var miss := {"hit": false, "safe_fraction": 1.0}
	var axis := a - b
	var length := axis.length()
	if length <= 0.0001:
		return miss
	_shape.radius = radius
	_shape.height = length + radius * 2.0
	_query.shape = _shape
	_query.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis / length)), (a + b) * 0.5)
	_query.motion = motion
	_query.margin = CONTACT_MARGIN
	_query.collision_mask = mask
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	_query.exclude = exclude
	var cast := space.cast_motion(_query)
	if cast.size() < 2:
		return miss
	var safe_fraction := clampf(float(cast[0]), 0.0, 1.0)
	var impact_query := PhysicsShapeQueryParameters3D.new()
	impact_query.shape = _shape
	impact_query.transform = _query.transform.translated(motion * clampf(float(cast[1]), 0.0, 1.0))
	impact_query.motion = Vector3.ZERO
	impact_query.margin = CONTACT_MARGIN
	impact_query.collision_mask = mask
	impact_query.collide_with_bodies = true
	impact_query.collide_with_areas = false
	impact_query.exclude = exclude
	var contact := space.get_rest_info(impact_query)
	return {
		"hit": true,
		"safe_fraction": safe_fraction,
		"unsafe_fraction": clampf(float(cast[1]), 0.0, 1.0),
		"normal": contact.get("normal", -motion.normalized()) as Vector3,
		"position": contact.get("point", a + motion * safe_fraction) as Vector3,
		"collider": contact.get("collider"),
		"collider_id": int(contact.get("collider_id", 0)),
	}
