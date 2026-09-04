class_name ParkSpotSpec
extends Resource

@export var id: StringName
@export var display_name := ""
@export var anchor := Vector3.ZERO
@export var marker_position := Vector3.ZERO
@export var recommended_marker_position := Vector3.ZERO
@export var intent_tags: Array[StringName] = []
@export var feature_ids: Array[StringName] = []
@export var route_feature_ids: Dictionary = {}
@export var route_intent: Dictionary = {}
@export var recovery_feature_ids: Array[StringName] = []

static func create(
	spot_id: StringName,
	spot_name: String,
	spot_anchor: Vector3,
	marker_position: Vector3,
	tags: Array[StringName],
	features: Array[StringName]
) -> ParkSpotSpec:
	var spec := ParkSpotSpec.new()
	spec.id = spot_id
	spec.display_name = spot_name
	spec.anchor = spot_anchor
	spec.marker_position = marker_position
	spec.recommended_marker_position = marker_position
	spec.intent_tags = tags
	spec.feature_ids = features
	return spec

func has_route(route: StringName) -> bool:
	return not (route_feature_ids.get(route, []) as Array).is_empty()

func features_for_route(route: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in route_feature_ids.get(route, []):
		result.append(StringName(value))
	return result
