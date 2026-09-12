class_name SessionYardCourseProfile
extends ParkCourseProfile

func spawn_world_z() -> float:
	return 42.0

func finish_trigger_world_z() -> float:
	# The Terrain Only challenge completes on the terrain-line pad, whose
	# downslope extent ends near z = -36. The finish must sit below that so
	# the run cannot preempt the last required feature use.
	return -42.0

func feature_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = [
		{"kind": "gate", "name": "YardStartGate", "x": 0.0, "z": 42.0, "width": 18.0, "color": Color("#55d6be"), "route": &"safe"},
		{"kind": "roller", "name": "YardSetupRoller", "x": 0.0, "z": 34.0, "length": 6.0, "height": 0.5, "width": 13.0, "route": &"safe"},
		{"kind": "tabletop", "name": "YardSmallJump", "x": -12.0, "z": 22.0, "speed": 13.0, "lip": 6.5, "width": 7.0, "pop": 0.68, "route": &"safe"},
		{"kind": "tabletop", "name": "YardMediumJump", "x": -12.0, "z": -3.0, "speed": 17.0, "lip": 8.5, "width": 8.0, "pop": 0.72, "route": &"intermediate"},
		{"kind": "rail", "name": "YardFlatBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.1, "friction": 1.0, "approach": 50.0, "points": [Vector3(10.0, 25.0, 0.2), Vector3(10.0, 10.0, 0.2)], "route": &"intermediate"},
		{"kind": "rail", "name": "YardCurveRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.64, "approach": 40.0, "points": [Vector3(13.0, 2.0, 0.16), Vector3(10.0, -7.0, 0.55), Vector3(12.0, -16.0, 0.55), Vector3(17.0, -24.0, 0.16)], "route": &"expert"},
		{"kind": "side_hit", "name": "YardSideHit", "x": 25.0, "z": 17.0, "length": 9.0, "height": 1.25, "width": 7.0, "yaw": 20.0, "route": &"intermediate"},
		{"kind": "berm", "name": "YardRecoveryBank", "x": 24.0, "z": -12.0, "length": 18.0, "width": 9.0, "bank": -14.0, "yaw": 12.0, "route": &"safe"},
		{"kind": "wallride", "name": "YardWall", "x": 30.0, "z": -25.0, "length": 14.0, "height": 4.0, "yaw": -8.0, "route": &"expert", "color": Color("#ef8354")},
		{"kind": "butter", "name": "YardTerrainLine", "x": -1.0, "z": -28.0, "length": 16.0, "width": 10.0, "height": 0.12, "route": &"safe"},
	]
	for index: int in specs.size():
		var spec: Dictionary = specs[index]
		var kind := str(spec.get("kind", "feature"))
		var route := StringName(spec.get("route", &"intermediate"))
		var discipline := ParkCourseProfile._discipline_for_kind(kind)
		var defaults := _asset_contract_defaults(kind)
		spec["feature_id"] = StringName(str(spec.name).to_snake_case())
		spec["spot_id"] = &"session_yard"
		spec["discipline"] = discipline
		spec["skill_floor"] = 0 if route == &"safe" else (1 if route == &"intermediate" else 2)
		spec["skill_ceiling"] = 3 if route == &"safe" else (4 if route == &"intermediate" else 5)
		spec["intent_tags"] = [StringName(kind), discipline, route, &"rapid_retry"]
		spec["risk_level"] = 0 if route == &"safe" else (1 if route == &"intermediate" else 3)
		spec["hero_feature"] = str(spec.name) in ["YardMediumJump", "YardCurveRail"]
		spec["optional"] = route == &"expert"
		for key: String in ["asset_id", "asset_class", "collision_policy", "readability_category"]:
			if not spec.has(key):
				spec[key] = defaults[key]
		spec["scale_override"] = float(spec.get("scale_override", 1.0))
	return specs

func spot_specs() -> Array[ParkSpotSpec]:
	var ids: Array[StringName] = []
	var features := feature_specs()
	for spec: Dictionary in features:
		ids.append(StringName(spec.feature_id))
	var spot := ParkSpotSpec.create(
		&"session_yard", "Session Yard", Vector3(3.0, 0.0, 2.0), Vector3(0.0, 0.0, 46.0),
		[&"rapid_retry", &"progression", &"terrain_line"], ids
	)
	spot.route_feature_ids = {&"safe": [], &"intermediate": [], &"expert": []}
	spot.route_intent = {
		&"safe": "central setup, terrain line, and recovery bank",
		&"intermediate": "small/medium jumps and box progression",
		&"expert": "curved rail and wall commitment",
	}
	for spec: Dictionary in features:
		var feature_id := StringName(spec.feature_id)
		var route := StringName(spec.route)
		(spot.route_feature_ids[route] as Array).append(feature_id)
		if route == &"safe":
			spot.recovery_feature_ids.append(feature_id)
	return [spot]

func challenge_specs() -> Array[ParkChallengeSpec]:
	return [
		ParkChallengeSpec.create(&"yard_any_rail", "Lap a Rail", "Grind either yard rail and land clean.", &"session_yard", [&"yard_flat_box", &"yard_curve_rail"], [
			{"kind": &"grind"}, {"kind": &"clean_landing"}, {"kind": &"no_bail"},
		]),
		ParkChallengeSpec.create(&"yard_terrain_only", "Terrain Only", "Finish the safe route without grinding a rail.", &"session_yard", [&"yard_setup_roller", &"yard_small_jump", &"yard_terrain_line"], [
			{"kind": &"feature_sequence", "feature_ids": [&"yard_setup_roller", &"yard_small_jump", &"yard_terrain_line"]}, {"kind": &"finish_route", "route": &"safe"}, {"kind": &"no_bail"},
		]),
	]
