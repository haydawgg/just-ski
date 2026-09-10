class_name EquipmentFeatureCollisionSolver
extends RefCounted

## Sweeps the visible ski envelopes against solid park features. Terrain is
## intentionally excluded: the existing per-ski contact and suspension system
## remains the sole owner of snow contact.

const FEATURE_MASK := 4
const SKI_RADIUS := 0.075
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
		var length := axis.length()
		if length <= 0.2:
			continue
		_shape.radius = SKI_RADIUS
		_shape.height = length + SKI_RADIUS * 2.0
		_query.shape = _shape
		_query.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis / length)), (nose + tail) * 0.5)
		_query.motion = motion
		_query.margin = CONTACT_MARGIN
		_query.collision_mask = FEATURE_MASK
		_query.collide_with_bodies = true
		_query.collide_with_areas = false
		_query.exclude = exclude
		var cast := space.cast_motion(_query)
		if cast.size() < 2:
			continue
		var safe_fraction := clampf(float(cast[0]), 0.0, 1.0)
		if safe_fraction >= float(best.safe_fraction):
			continue
		var impact_query := PhysicsShapeQueryParameters3D.new()
		impact_query.shape = _shape
		impact_query.transform = _query.transform.translated(motion * clampf(float(cast[1]), 0.0, 1.0))
		impact_query.motion = Vector3.ZERO
		impact_query.margin = CONTACT_MARGIN
		impact_query.collision_mask = FEATURE_MASK
		impact_query.collide_with_bodies = true
		impact_query.collide_with_areas = false
		impact_query.exclude = exclude
		var contact := space.get_rest_info(impact_query)
		best = {
			"hit": true,
			"side": side,
			"safe_fraction": safe_fraction,
			"unsafe_fraction": clampf(float(cast[1]), 0.0, 1.0),
			"normal": contact.get("normal", -motion.normalized()) as Vector3,
			"position": contact.get("point", nose + motion * safe_fraction) as Vector3,
			"collider": contact.get("collider"),
			"collider_id": int(contact.get("collider_id", 0)),
		}
	return best
