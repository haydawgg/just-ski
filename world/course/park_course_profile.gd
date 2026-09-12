class_name ParkCourseProfile
extends Resource

@export_category("Feature Readability")
@export var snow_feature_marker_color := Color("#168fa8")
@export var solid_feature_color := Color("#d9673f")
@export var grind_feature_color := Color("#c76833")
@export var guide_feature_color := Color("#35cbb6")
@export var boundary_feature_color := Color("#e9a13b")
@export_range(0.08, 0.5, 0.01) var takeoff_marker_depth := 0.44
@export_range(1.0, 6.0, 0.1) var landing_marker_length := 4.5
@export_range(0.04, 0.3, 0.01) var landing_marker_width := 0.22
@export_range(0.005, 0.08, 0.005) var marker_surface_offset := 0.032

func spawn_world_z() -> float:
	return 138.0

func finish_trigger_world_z() -> float:
	# Phase 8: the finish sits ~64 slope metres downhill of the LargeTable
	# structure end, on the flat BottomHub pad whose crease is 5 m uphill.
	return -227.0

func feature_readability() -> Dictionary:
	return {
		"color": snow_feature_marker_color,
		"solid_feature_color": solid_feature_color,
		"grind_feature_color": grind_feature_color,
		"guide_color": guide_feature_color,
		"boundary_color": boundary_feature_color,
		"takeoff_depth": takeoff_marker_depth,
		"landing_length": landing_marker_length,
		"landing_width": landing_marker_width,
		"surface_offset": marker_surface_offset,
	}

func feature_specs() -> Array[Dictionary]:
	# Phase 8 three-jump hero line (SmallTable -> MediumTable -> LargeTable),
	# each at x = -12 with ~62/72 slope-metre recovery zones and a runout of
	# ~64 slope metres before the finish. Side content that used to sit on the
	# hero lane was moved laterally (UpperRoller, HipTransfer) or downhill
	# with its spot (technical yard, transfer zone, lower hero, finale).
	# StepDownTable was removed; see _content_placement_for for the finale
	# intermediate-route migration.
	var specs: Array[Dictionary] = [
		# Summit teaching cluster (unchanged: spawn acceleration + safe line).
		{"kind": "gate", "name": "SummitStartGate", "x": 0.0, "z": 134.0, "width": 13.0, "color": Color("#55d6be")},
		{"kind": "roller", "name": "SummitRollerA", "x": 0.0, "z": 128.0, "length": 5.0, "height": 0.42, "width": 10.0},
		{"kind": "roller", "name": "SummitRollerB", "x": 0.0, "z": 120.0, "length": 5.5, "height": 0.5, "width": 10.0},
		{"kind": "tabletop", "name": "SmallTable", "discipline": &"air", "difficulty": "beginner", "x": -12.0, "z": 110.0, "speed": 15.0, "lip": 7.0, "width": 9.0, "pop": 0.72},
		{"kind": "rail", "name": "SummitFlatBox", "discipline": &"jib", "difficulty": "beginner", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.2, "friction": 1.15, "approach": 52.0, "drift_bias": -0.18, "points": [Vector3(12.0, 124.0, 0.22), Vector3(12.0, 112.0, 0.22)]},
		{"kind": "rail", "name": "BeginnerTube", "discipline": &"jib", "difficulty": "beginner", "rail_type": GrindRail3D.RailType.PIPE, "radius": 1.0, "friction": 0.7, "approach": 48.0, "drift_bias": 0.14, "points": [Vector3(12.0, 106.0, 0.16), Vector3(12.0, 96.0, 0.16)]},

		# Upper fork: beside Jump 1, clear of the landing lane.
		{"kind": "side_hit", "name": "UpperLeftSideHit", "x": -23.5, "z": 96.0, "length": 9.0, "height": 1.25, "width": 7.0, "yaw": -18.0},
		{"kind": "roller", "name": "UpperRoller", "x": 16.0, "z": 96.0, "length": 8.0, "height": 0.8, "width": 9.0},
		{"kind": "berm", "name": "UpperBermLeft", "x": 0.0, "z": 98.0, "length": 14.0, "width": 6.0, "bank": 13.0, "yaw": -16.0},
		{"kind": "berm", "name": "UpperBermRight", "x": 2.0, "z": 82.0, "length": 14.0, "width": 6.0, "bank": -13.0, "yaw": 16.0},
		{"kind": "rail", "name": "DownRail", "discipline": &"jib", "difficulty": "beginner", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.55, "approach": 42.0, "drift_bias": -0.22, "points": [Vector3(14.0, 90.0, 0.16), Vector3(14.0, 76.0, 0.16)]},
		{"kind": "bonk", "name": "UpperBonk", "x": 22.0, "z": 76.0, "height": 1.3, "radius": 0.42, "color": Color("#ffc857")},

		# Mid park: Jump 2 (MediumTable) with the yard shifted downhill to
		# follow it; all yard content stays right of the hero lane.
		{"kind": "tabletop", "name": "MediumTable", "x": -12.0, "z": 12.0, "speed": 20.0, "lip": 9.5, "width": 10.5, "pop": 0.72},
		{"kind": "moguls", "name": "MidMoguls", "x": -1.0, "z": 27.0, "rows": 5, "spacing": 4.4, "height": 0.48, "width": 4.5},
		{"kind": "butter", "name": "MidButterPad", "x": 0.0, "z": 3.0, "length": 13.0, "width": 9.0, "height": 0.12},
		{"kind": "rail", "name": "KinkRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.7, "approach": 40.0, "drift_bias": 0.28, "points": [Vector3(10.0, 28.0, 0.16), Vector3(10.0, 18.0, 0.16), Vector3(15.0, 6.0, 0.16)]},
		{"kind": "rail", "name": "DFDBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.15, "friction": 1.05, "approach": 50.0, "drift_bias": -0.18, "points": [Vector3(10.0, 0.0, 0.22), Vector3(10.0, -12.0, -0.68), Vector3(10.0, -24.0, 0.22)]},
		{"kind": "wallride", "name": "MidWallride", "x": 24.0, "z": 5.0, "length": 13.0, "height": 4.0, "yaw": 8.0, "color": Color("#ef8354")},

		# Transfer zone: fills Recovery 2 to the right of the hero lane.
		{"kind": "hip", "name": "HipTransfer", "x": 18.0, "z": -42.0, "speed": 16.0, "lip": 8.0, "yaw": 28.0, "pop": 0.72},
		{"kind": "side_hit", "name": "CenterSpine", "x": 2.0, "z": -24.0, "length": 12.0, "height": 1.8, "width": 8.0, "yaw": -12.0},
		{"kind": "roller", "name": "MidRoller", "x": 2.0, "z": -62.0, "length": 9.0, "height": 0.7, "width": 12.0},
		{"kind": "rail", "name": "LongTube", "rail_type": GrindRail3D.RailType.PIPE, "radius": 0.76, "friction": 0.45, "approach": 40.0, "drift_bias": 0.20, "points": [Vector3(18.0, -46.0, 0.14), Vector3(18.0, -72.0, 0.14)]},
		{"kind": "rail", "name": "TransferBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.1, "friction": 0.95, "approach": 48.0, "drift_bias": -0.24, "points": [Vector3(14.0, -50.0, 0.22), Vector3(2.0, -76.0, 0.22)]},
		{"kind": "bonk", "name": "TransferBonk", "x": 24.0, "z": -62.0, "height": 1.8, "radius": 0.5, "color": Color("#55d6be")},

		# Lower park: Jump 3 (LargeTable) with its side content.
		{"kind": "tabletop", "name": "LargeTable", "x": -12.0, "z": -106.0, "speed": 23.0, "lip": 11.5, "width": 11.5, "pop": 0.72},
		{"kind": "side_hit", "name": "LowerRightSideHit", "x": 25.0, "z": -106.0, "length": 10.0, "height": 1.45, "width": 7.0, "yaw": 22.0},
		{"kind": "butter", "name": "LowerButterPad", "x": 1.0, "z": -118.0, "length": 16.0, "width": 10.0, "height": 0.14},
		{"kind": "rail", "name": "SRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.8, "friction": 0.7, "approach": 38.0, "drift_bias": 0.30, "points": [Vector3(16.0, -98.0, 0.16), Vector3(9.0, -110.0, 0.16), Vector3(16.0, -122.0, 0.16)]},
		{"kind": "rail", "name": "Rainbow", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.6, "approach": 40.0, "drift_bias": -0.28, "points": [Vector3(16.0, -124.0, 0.16), Vector3(16.0, -132.0, 3.2), Vector3(16.0, -144.0, 0.16)]},
		{"kind": "wallride", "name": "LowerWallride", "x": 27.0, "z": -135.0, "length": 15.0, "height": 4.5, "yaw": -8.0, "color": Color("#55d6be")},

		# Finale: runout side content after Jump 3, then the finish.
		{"kind": "cannon", "name": "FinalCannon", "x": 14.0, "z": -167.0, "length": 11.0, "width": 5.5, "height": 1.7},
		{"kind": "rail", "name": "FinalBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.05, "friction": 1.1, "approach": 46.0, "drift_bias": 0.18, "points": [Vector3(8.0, -172.0, 0.22), Vector3(8.0, -194.0, 0.22)]},
		{"kind": "rail", "name": "FinalDFDRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.8, "friction": 0.68, "approach": 38.0, "drift_bias": -0.30, "points": [Vector3(18.0, -168.0, 0.18), Vector3(18.0, -178.0, 0.75), Vector3(18.0, -190.0, 0.18)]},
		{"kind": "berm", "name": "FinalCatchBerm", "x": 5.0, "z": -204.0, "length": 18.0, "width": 14.0, "bank": 9.0, "yaw": 0.0},
		{"kind": "gate", "name": "FinishGate", "x": 0.0, "z": -222.0, "width": 50.0, "color": Color("#ff9f1c")},
	]
	# Every feature carries an explicit asset/affordance contract. Individual
	# course authors may override these keys in the table above; these defaults
	# keep older profiles valid while still making the runtime decision visible.
	for spec: Dictionary in specs:
		_apply_content_semantics(spec)
		var defaults := _asset_contract_defaults(str(spec.get("kind", "feature")))
		if not spec.has("asset_id"):
			spec["asset_id"] = defaults.asset_id
		if not spec.has("asset_class"):
			spec["asset_class"] = defaults.asset_class
		if not spec.has("collision_policy"):
			spec["collision_policy"] = defaults.collision_policy
		if not spec.has("readability_category"):
			spec["readability_category"] = defaults.readability_category
		if not spec.has("scale_override"):
			# The catalog route-gate scene is authored at the 13 m teaching-gate
			# width; the finish gate intentionally scales that same asset to its
			# wider course boundary.
			spec["scale_override"] = clampf(float(spec.get("width", 13.0)) / 13.0, 0.5, 6.0) if str(spec.get("kind", "")) == "gate" else 1.0
	return specs

func spot_specs() -> Array[ParkSpotSpec]:
	var spots: Array[ParkSpotSpec] = [
		ParkSpotSpec.create(
			&"summit_fundamentals", "Summit Fundamentals", Vector3(0.0, 0.0, 116.0), Vector3(0.0, 0.0, 138.0),
			[&"learn", &"flow", &"first_jib"], _feature_ids(["SummitStartGate", "SummitRollerA", "SummitRollerB", "SmallTable", "SummitFlatBox", "BeginnerTube"])
		),
		ParkSpotSpec.create(
			&"upper_fork", "Upper Fork", Vector3(0.0, 0.0, 86.0), Vector3(0.0, 0.0, 104.0),
			[&"choice", &"side_hit", &"carve"], _feature_ids(["UpperLeftSideHit", "UpperRoller", "UpperBermLeft", "UpperBermRight", "DownRail", "UpperBonk"])
		),
		ParkSpotSpec.create(
			&"technical_yard", "Technical Yard", Vector3(3.0, 0.0, -5.0), Vector3(0.0, 0.0, 28.0),
			[&"technical", &"jib", &"terrain"], _feature_ids(["MediumTable", "MidMoguls", "MidButterPad", "KinkRail", "DFDBox", "MidWallride"])
		),
		ParkSpotSpec.create(
			&"transfer_zone", "Transfer Zone", Vector3(6.0, 0.0, -58.0), Vector3(0.0, 0.0, -24.0),
			[&"transfer", &"side_hit", &"line_choice"], _feature_ids(["HipTransfer", "CenterSpine", "MidRoller", "LongTube", "TransferBox", "TransferBonk"])
		),
		ParkSpotSpec.create(
			&"lower_hero", "Lower Hero and Rainbow", Vector3(8.0, 0.0, -124.0), Vector3(0.0, 0.0, -80.0),
			[&"hero", &"rainbow", &"progression"], _feature_ids(["LargeTable", "LowerRightSideHit", "LowerButterPad", "SRail", "Rainbow", "LowerWallride"])
		),
		ParkSpotSpec.create(
			&"finale", "Finale", Vector3(6.0, 0.0, -192.0), Vector3(0.0, 0.0, -152.0),
			[&"finale", &"commitment", &"runout"], _feature_ids(["FinalCannon", "FinalBox", "FinalDFDRail", "FinalCatchBerm", "FinishGate"])
		),
	]
	var features := feature_specs()
	for spot: ParkSpotSpec in spots:
		spot.route_feature_ids = {&"safe": [], &"intermediate": [], &"expert": []}
		spot.route_intent = {
			&"safe": "bypass, speed control, and recovery",
			&"intermediate": "deliberate feature timing and basic style",
			&"expert": "transfer, balance, and linked feature commitment",
		}
		for feature: Dictionary in features:
			if StringName(feature.get("spot_id", &"")) != spot.id:
				continue
			var feature_id := StringName(feature.get("feature_id", &""))
			var route := StringName(feature.get("route", &"intermediate"))
			(spot.route_feature_ids[route] as Array).append(feature_id)
			if &"recovery" in (feature.get("intent_tags", []) as Array) or &"bypass" in (feature.get("intent_tags", []) as Array):
				spot.recovery_feature_ids.append(feature_id)
	return spots

func challenge_specs() -> Array[ParkChallengeSpec]:
	return [
		ParkChallengeSpec.create(&"summit_grab_and_land", "Grab and Set It Down", "Use any summit air, hold a grab, and land.", &"summit_fundamentals", _feature_ids(["SmallTable"]), [
			{"kind": &"grab_and_land"}, {"kind": &"no_bail"},
		]),
		ParkChallengeSpec.create(&"upper_side_hit_straight", "Straight Through the Fork", "Take the intermediate route with less than 45 degrees of rotation and land clean.", &"upper_fork", _feature_ids(["UpperLeftSideHit"]), [
			{"kind": &"air_rotation", "maximum_degrees": 45.0}, {"kind": &"clean_landing"}, {"kind": &"no_bail"}, {"kind": &"finish_route", "route": &"intermediate"},
		]),
		ParkChallengeSpec.create(&"technical_kink_clean", "Clean the Kink", "Grind the Kink Rail and ride away clean.", &"technical_yard", _feature_ids(["KinkRail"]), [
			{"kind": &"grind", "feature_id": &"kink_rail"}, {"kind": &"clean_landing"}, {"kind": &"no_bail"},
		]),
		ParkChallengeSpec.create(&"transfer_expert_link", "Transfer Link", "Link the hip into the transfer box, score 1,400, and finish the expert route.", &"transfer_zone", _feature_ids(["HipTransfer", "TransferBox"]), [
			{"kind": &"feature_sequence", "feature_ids": [&"hip_transfer", &"transfer_box"]}, {"kind": &"minimum_score", "points": 1400}, {"kind": &"finish_route", "route": &"expert"}, {"kind": &"no_bail"},
		]),
		ParkChallengeSpec.create(&"lower_rainbow_grab", "Rainbow Style", "Grind the Rainbow, then grab and land the follow-up.", &"lower_hero", _feature_ids(["Rainbow"]), [
			{"kind": &"grind", "feature_id": &"rainbow"}, {"kind": &"grab_and_land", "after": {"kind": &"grind", "feature_id": &"rainbow"}}, {"kind": &"no_bail"},
		]),
		ParkChallengeSpec.create(&"finale_clean_360", "Finale 360", "Rotate at least 360 degrees, land clean, and finish through the expert route without bailing.", &"finale", _feature_ids(["FinalCannon"]), [
			{"kind": &"air_rotation", "minimum_degrees": 360.0}, {"kind": &"clean_landing"}, {"kind": &"no_bail"}, {"kind": &"finish_route", "route": &"expert"},
		]),
	]

func validate_content() -> Array[String]:
	var errors := validate_content_specs(feature_specs(), spot_specs())
	errors.append_array(validate_challenge_specs(challenge_specs(), feature_specs(), spot_specs()))
	return errors

static func validate_content_specs(features: Array[Dictionary], spots: Array[ParkSpotSpec]) -> Array[String]:
	var errors: Array[String] = []
	var feature_ids: Dictionary = {}
	var feature_names: Dictionary = {}
	var spot_ids: Dictionary = {}
	var valid_kinds := [&"tabletop", &"hip", &"roller", &"rail", &"berm", &"moguls", &"butter", &"side_hit", &"wallride", &"bonk", &"cannon", &"gate"]
	var valid_routes := [&"safe", &"intermediate", &"expert"]
	var valid_disciplines := [&"air", &"jib", &"flow", &"guide", &"terrain"]
	for spot: ParkSpotSpec in spots:
		if spot == null or spot.id == &"":
			errors.append("Spot IDs must be non-empty")
			continue
		if spot_ids.has(spot.id):
			errors.append("Duplicate spot ID: %s" % spot.id)
		spot_ids[spot.id] = spot
	for feature: Dictionary in features:
		var feature_id := StringName(feature.get("feature_id", &""))
		var feature_name := str(feature.get("name", ""))
		var kind := StringName(feature.get("kind", &""))
		var route := StringName(feature.get("route", &""))
		var discipline := StringName(feature.get("discipline", &""))
		if feature_id == &"" or feature_ids.has(feature_id):
			errors.append("Missing or duplicate feature ID: %s" % feature_id)
		feature_ids[feature_id] = feature
		if feature_name.is_empty() or feature_names.has(feature_name):
			errors.append("Missing or duplicate feature name: %s" % feature_name)
		feature_names[feature_name] = true
		if kind not in valid_kinds:
			errors.append("Invalid feature kind on %s: %s" % [feature_name, kind])
		if route not in valid_routes:
			errors.append("Invalid route tier on %s: %s" % [feature_name, route])
		if discipline not in valid_disciplines:
			errors.append("Invalid discipline on %s: %s" % [feature_name, discipline])
		if not spot_ids.has(StringName(feature.get("spot_id", &""))):
			errors.append("Invalid spot ID on %s" % feature_name)
		if kind == &"rail" and (feature.get("points", []) as Array).size() < 2:
			errors.append("Rail %s needs at least two points" % feature_name)
		for dimension: String in ["width", "length", "height", "radius"]:
			if feature.has(dimension) and float(feature[dimension]) <= 0.0:
				errors.append("%s has invalid %s" % [feature_name, dimension])
	var referenced_features: Dictionary = {}
	for spot_id: StringName in spot_ids:
		var spot: ParkSpotSpec = spot_ids[spot_id]
		for feature_id: StringName in spot.feature_ids:
			referenced_features[feature_id] = true
			if not feature_ids.has(feature_id):
				errors.append("Spot %s references missing feature %s" % [spot_id, feature_id])
			elif StringName((feature_ids[feature_id] as Dictionary).get("spot_id", &"")) != spot_id:
				errors.append("Feature %s is assigned to a different spot" % feature_id)
	for feature_id: StringName in feature_ids:
		if not referenced_features.has(feature_id):
			errors.append("Feature %s is not referenced by any spot" % feature_id)
	return errors

static func validate_challenge_specs(challenges: Array[ParkChallengeSpec], features: Array[Dictionary], spots: Array[ParkSpotSpec]) -> Array[String]:
	var errors: Array[String] = []
	var challenge_ids: Dictionary = {}
	var feature_ids: Dictionary = {}
	var spot_ids: Dictionary = {}
	for feature: Dictionary in features:
		feature_ids[StringName(feature.get("feature_id", &""))] = true
	for spot: ParkSpotSpec in spots:
		if spot != null:
			spot_ids[spot.id] = true
	for challenge: ParkChallengeSpec in challenges:
		if challenge == null or challenge.id == &"":
			errors.append("Challenge IDs must be non-empty")
			continue
		if challenge_ids.has(challenge.id):
			errors.append("Duplicate challenge ID: %s" % challenge.id)
		challenge_ids[challenge.id] = true
		if not spot_ids.has(challenge.spot_id):
			errors.append("Challenge %s references invalid spot %s" % [challenge.id, challenge.spot_id])
		if challenge.conditions.is_empty():
			errors.append("Challenge %s has no conditions" % challenge.id)
		for feature_id: StringName in challenge.feature_ids:
			if not feature_ids.has(feature_id):
				errors.append("Challenge %s references invalid feature %s" % [challenge.id, feature_id])
	return errors

func _apply_content_semantics(spec: Dictionary) -> void:
	var feature_name := str(spec.get("name", "ParkFeature"))
	var kind := str(spec.get("kind", "feature"))
	var placement := _content_placement_for(feature_name)
	var discipline := StringName(spec.get("discipline", _discipline_for_kind(kind)))
	spec["feature_id"] = StringName(feature_name.to_snake_case())
	spec["spot_id"] = placement.spot_id
	spec["route"] = placement.route
	spec["discipline"] = discipline
	spec["skill_floor"] = placement.skill_floor
	spec["skill_ceiling"] = placement.skill_ceiling
	spec["risk_level"] = placement.risk_level
	spec["hero_feature"] = feature_name in ["SmallTable", "MediumTable", "LargeTable", "UpperLeftSideHit", "KinkRail", "HipTransfer", "Rainbow", "FinalCannon"]
	spec["optional"] = placement.route == &"expert"
	var tags: Array[StringName] = [StringName(kind), discipline, placement.route]
	if bool(spec["hero_feature"]):
		tags.append(&"hero")
	if kind in ["berm", "roller", "butter", "gate"]:
		tags.append(&"recovery")
	if placement.route == &"safe":
		tags.append(&"bypass")
	elif placement.route == &"expert":
		tags.append(&"transfer")
	spec["intent_tags"] = tags

static func _discipline_for_kind(kind: String) -> StringName:
	match kind:
		"tabletop", "hip", "side_hit", "cannon":
			return &"air"
		"rail", "wallride", "bonk":
			return &"jib"
		"roller", "berm", "moguls", "butter":
			return &"flow"
		"gate":
			return &"guide"
		_:
			return &"terrain"

func _content_placement_for(feature_name: String) -> Dictionary:
	var spot_by_feature := {
		"SummitStartGate": &"summit_fundamentals", "SummitRollerA": &"summit_fundamentals", "SummitRollerB": &"summit_fundamentals", "SmallTable": &"summit_fundamentals", "SummitFlatBox": &"summit_fundamentals", "BeginnerTube": &"summit_fundamentals",
		"UpperLeftSideHit": &"upper_fork", "UpperRoller": &"upper_fork", "UpperBermLeft": &"upper_fork", "UpperBermRight": &"upper_fork", "DownRail": &"upper_fork", "UpperBonk": &"upper_fork",
		"MediumTable": &"technical_yard", "MidMoguls": &"technical_yard", "MidButterPad": &"technical_yard", "KinkRail": &"technical_yard", "DFDBox": &"technical_yard", "MidWallride": &"technical_yard",
		"HipTransfer": &"transfer_zone", "CenterSpine": &"transfer_zone", "MidRoller": &"transfer_zone", "LongTube": &"transfer_zone", "TransferBox": &"transfer_zone", "TransferBonk": &"transfer_zone",
		"LargeTable": &"lower_hero", "LowerRightSideHit": &"lower_hero", "LowerButterPad": &"lower_hero", "SRail": &"lower_hero", "Rainbow": &"lower_hero", "LowerWallride": &"lower_hero",
		"FinalCannon": &"finale", "FinalBox": &"finale", "FinalDFDRail": &"finale", "FinalCatchBerm": &"finale", "FinishGate": &"finale",
	}
	# StepDownTable was removed in the Phase 8 three-jump migration. The
	# FinalCatchBerm moves from safe to intermediate so the finale keeps a
	# feature-backed route for all three tiers after StepDownTable's exit.
	var safe := ["SummitStartGate", "SummitRollerA", "SummitRollerB", "UpperRoller", "UpperBermLeft", "UpperBermRight", "MidMoguls", "MidButterPad", "MidRoller", "LowerButterPad", "FinalBox", "FinishGate"]
	var expert := ["BeginnerTube", "UpperBonk", "KinkRail", "MidWallride", "CenterSpine", "TransferBox", "TransferBonk", "LowerRightSideHit", "Rainbow", "LowerWallride", "FinalCannon", "FinalDFDRail"]
	var route: StringName = &"safe" if feature_name in safe else (&"expert" if feature_name in expert else &"intermediate")
	var floor := 0 if route == &"safe" else (1 if route == &"intermediate" else 2)
	var ceiling := 2 if route == &"safe" else (4 if route == &"intermediate" else 5)
	var risk := 0 if route == &"safe" else (1 if route == &"intermediate" else 3)
	return {"spot_id": spot_by_feature.get(feature_name, &""), "route": route, "skill_floor": floor, "skill_ceiling": ceiling, "risk_level": risk}

func _feature_ids(names: Array[String]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for feature_name: String in names:
		ids.append(StringName(feature_name.to_snake_case()))
	return ids

func _asset_contract_defaults(kind: String) -> Dictionary:
	match kind:
		"gate":
			return {"asset_id": "route_gate", "asset_class": 2, "collision_policy": "GUIDE", "readability_category": "guide"}
		"rail":
			return {"asset_id": "grind_rail", "asset_class": 1, "collision_policy": "GRIND_ONLY", "readability_category": "jib"}
		"roller", "tabletop", "hip", "berm", "moguls", "butter", "side_hit", "wallride", "bonk", "cannon":
			return {"asset_id": "snow_feature", "asset_class": 0, "collision_policy": "SOLID", "readability_category": "terrain_feature"}
		_:
			return {"asset_id": "course_landmark", "asset_class": 2, "collision_policy": "GUIDE", "readability_category": "landmark"}
