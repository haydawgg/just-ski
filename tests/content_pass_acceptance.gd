extends Node

const EXPECTED_SPOTS := [
	&"summit_fundamentals",
	&"upper_fork",
	&"technical_yard",
	&"transfer_zone",
	&"lower_hero",
	&"finale",
]
const REQUIRED_ROUTES := [&"safe", &"intermediate", &"expert"]
const REQUIRED_DISCIPLINES := [&"air", &"jib", &"flow", &"guide", &"terrain"]
const REQUIRED_FEATURE_FIELDS := [
	"feature_id",
	"spot_id",
	"route",
	"discipline",
	"skill_floor",
	"skill_ceiling",
	"intent_tags",
	"risk_level",
	"hero_feature",
	"optional",
]

var failures: Array[String] = []

func _ready() -> void:
	var profile := ParkCourseProfile.new()
	var features := profile.feature_specs()
	var spots := profile.spot_specs()
	_validate_features(features)
	_validate_spots(features, spots)
	_validate_profile_contract(profile)
	_validate_rejected_content(profile)
	if failures.is_empty():
		print("CONTENT_PASS_ACCEPTANCE_PASS: six sessionable spots, route tiers, disciplines, metadata, and references validated")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CONTENT_PASS_ACCEPTANCE_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _validate_features(features: Array[Dictionary]) -> void:
	var feature_ids: Dictionary = {}
	var names: Dictionary = {}
	for spec: Dictionary in features:
		var label := str(spec.get("name", "<unnamed>"))
		for field: String in REQUIRED_FEATURE_FIELDS:
			if not spec.has(field):
				failures.append("%s is missing %s" % [label, field])
		var feature_id := StringName(spec.get("feature_id", &""))
		if feature_id == &"":
			failures.append("%s has an empty feature_id" % label)
		elif feature_ids.has(feature_id):
			failures.append("duplicate feature_id %s" % feature_id)
		feature_ids[feature_id] = true
		if names.has(label):
			failures.append("duplicate feature name %s" % label)
		names[label] = true
		if StringName(spec.get("route", &"")) not in REQUIRED_ROUTES:
			failures.append("%s has invalid route %s" % [label, spec.get("route", "")])
		if StringName(spec.get("discipline", &"")) not in REQUIRED_DISCIPLINES:
			failures.append("%s has invalid discipline %s" % [label, spec.get("discipline", "")])
		if int(spec.get("skill_floor", -1)) < 0 or int(spec.get("skill_ceiling", -1)) > 5:
			failures.append("%s has invalid skill range" % label)
		if int(spec.get("skill_floor", 6)) > int(spec.get("skill_ceiling", -1)):
			failures.append("%s has an inverted skill range" % label)
		if not spec.get("intent_tags", []) is Array or (spec.get("intent_tags", []) as Array).is_empty():
			failures.append("%s needs at least one intent tag" % label)

func _validate_spots(features: Array[Dictionary], spots: Array[ParkSpotSpec]) -> void:
	if spots.size() != EXPECTED_SPOTS.size():
		failures.append("expected %d spots, found %d" % [EXPECTED_SPOTS.size(), spots.size()])
	var features_by_id: Dictionary = {}
	for spec: Dictionary in features:
		features_by_id[StringName(spec.get("feature_id", &""))] = spec
	var seen_spots: Dictionary = {}
	for spot: ParkSpotSpec in spots:
		if spot == null:
			failures.append("spot list contains null")
			continue
		if spot.id not in EXPECTED_SPOTS:
			failures.append("unexpected spot id %s" % spot.id)
		if seen_spots.has(spot.id):
			failures.append("duplicate spot id %s" % spot.id)
		seen_spots[spot.id] = true
		if spot.display_name.strip_edges().is_empty():
			failures.append("%s has no display name" % spot.id)
		if spot.feature_ids.size() < 3:
			failures.append("%s needs at least three distinct attempts" % spot.id)
		if spot.intent_tags.is_empty():
			failures.append("%s needs intent tags" % spot.id)
		if spot.recommended_marker_position.z <= spot.anchor.z:
			failures.append("%s marker is not practically uphill of the spot" % spot.id)
		if spot.marker_position != spot.recommended_marker_position:
			failures.append("%s marker aliases disagree" % spot.id)
		var routes: Dictionary = {}
		var route_positions: Dictionary = {}
		var has_recovery := false
		for feature_id: StringName in spot.feature_ids:
			if not features_by_id.has(feature_id):
				failures.append("%s references missing feature %s" % [spot.id, feature_id])
				continue
			var feature: Dictionary = features_by_id[feature_id]
			if StringName(feature.get("spot_id", &"")) != spot.id:
				failures.append("%s references feature %s owned by %s" % [spot.id, feature_id, feature.get("spot_id", "")])
			routes[StringName(feature.get("route", &""))] = true
			var position := Vector2(float(feature.get("x", 0.0)), float(feature.get("z", 0.0)))
			if StringName(feature.get("kind", &"")) == &"rail":
				var points := feature.get("points", []) as Array
				if not points.is_empty():
					var encoded := points[0] as Vector3
					position = Vector2(encoded.x, encoded.y)
			route_positions[StringName(feature.get("route", &""))] = position
			if &"recovery" in (feature.get("intent_tags", []) as Array) or &"bypass" in (feature.get("intent_tags", []) as Array):
				has_recovery = true
		for route: StringName in REQUIRED_ROUTES:
			if not routes.has(route):
				failures.append("%s is missing a %s route" % [spot.id, route])
			if not spot.has_route(route) or spot.features_for_route(route).is_empty():
				failures.append("%s has no feature-backed %s route" % [spot.id, route])
		for first_route: StringName in REQUIRED_ROUTES:
			for second_route: StringName in REQUIRED_ROUTES:
				if first_route >= second_route or not route_positions.has(first_route) or not route_positions.has(second_route):
					continue
				if (route_positions[first_route] as Vector2).distance_to(route_positions[second_route] as Vector2) < 1.0:
					failures.append("%s routes %s and %s share the same geometry" % [spot.id, first_route, second_route])
		if not has_recovery:
			failures.append("%s has no bypass/recovery content" % spot.id)
	for expected: StringName in EXPECTED_SPOTS:
		if not seen_spots.has(expected):
			failures.append("missing spot %s" % expected)

func _validate_profile_contract(profile: ParkCourseProfile) -> void:
	var errors := profile.validate_content()
	for error: String in errors:
		failures.append("profile validation: " + error)

func _validate_rejected_content(profile: ParkCourseProfile) -> void:
	var features := profile.feature_specs()
	var spots := profile.spot_specs()
	var invalid := features.duplicate(true)
	invalid[0]["feature_id"] = invalid[1]["feature_id"]
	invalid[0]["name"] = invalid[1]["name"]
	invalid[2]["kind"] = "unknown_feature"
	invalid[3]["width"] = -1.0
	invalid[4]["points"] = []
	invalid[5]["spot_id"] = &"missing_spot"
	invalid[6]["route"] = &"jib"
	invalid[7]["discipline"] = &"expert"
	var errors := ParkCourseProfile.validate_content_specs(invalid, spots)
	for expected: String in ["duplicate feature ID", "duplicate feature name", "Invalid feature kind", "invalid width", "needs at least two points", "Invalid spot ID", "Invalid route tier", "Invalid discipline"]:
		var found := false
		for error: String in errors:
			if expected.to_lower() in error.to_lower():
				found = true
				break
		if not found:
			failures.append("validator did not reject %s" % expected)
