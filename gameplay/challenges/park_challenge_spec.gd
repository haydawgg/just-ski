class_name ParkChallengeSpec
extends Resource

@export var id: StringName
@export var display_name := ""
@export var description := ""
@export var spot_id: StringName
@export var feature_ids: Array[StringName] = []
@export var conditions: Array[Dictionary] = []

static func create(
	challenge_id: StringName,
	challenge_name: String,
	challenge_description: String,
	challenge_spot_id: StringName,
	challenge_feature_ids: Array[StringName],
	challenge_conditions: Array[Dictionary]
) -> ParkChallengeSpec:
	var spec := ParkChallengeSpec.new()
	spec.id = challenge_id
	spec.display_name = challenge_name
	spec.description = challenge_description
	spec.spot_id = challenge_spot_id
	spec.feature_ids = challenge_feature_ids
	spec.conditions = challenge_conditions
	return spec
