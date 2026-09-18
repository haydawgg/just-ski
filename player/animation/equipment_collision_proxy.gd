class_name EquipmentCollisionProxy
extends RefCounted

## One semantic capsule in the presentation self-collision model. Spheres use
## identical endpoints. Proxies sharing an actuator move as one rigid group.

enum Kind {
	BODY,
	SKI,
	BOOT,
	POLE,
}

enum Mobility {
	FIXED,
	TRANSLATE,
	PIVOT,
}

var id: StringName
var kind: int = Kind.BODY
var side: StringName = &"center"
var a := Vector3.ZERO
var b := Vector3.ZERO
var radius := 0.0
var actuator: StringName
var mobility: int = Mobility.FIXED
var pivot := Vector3.ZERO
var tags: Array[StringName] = []
var max_translation := 0.35
var max_angle := 1.2

func copy() -> EquipmentCollisionProxy:
	var duplicate := EquipmentCollisionProxy.new()
	duplicate.id = id
	duplicate.kind = kind
	duplicate.side = side
	duplicate.a = a
	duplicate.b = b
	duplicate.radius = radius
	duplicate.actuator = actuator
	duplicate.mobility = mobility
	duplicate.pivot = pivot
	duplicate.tags = tags.duplicate()
	duplicate.max_translation = max_translation
	duplicate.max_angle = max_angle
	return duplicate

func center() -> Vector3:
	return (a + b) * 0.5

func is_valid() -> bool:
	return not id.is_empty() and a.is_finite() and b.is_finite() \
		and is_finite(radius) and radius >= 0.0 and pivot.is_finite()
