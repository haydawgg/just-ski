class_name ParkCourseBuilder
extends RefCounted

const ParkLayout := preload("res://world/park_features/park_layout.gd")

static func build(parent: Node3D, profile: ParkCourseProfile, physics_profile: SkiPhysicsProfile) -> Dictionary:
	var built: Dictionary = {}
	if profile == null:
		push_warning("ParkCourseBuilder received no course profile")
		return built
	if physics_profile == null:
		push_warning("ParkCourseBuilder received no ski physics profile")
		return built
	for spec: Dictionary in profile.feature_specs():
		var feature := _build_feature(parent, spec, physics_profile)
		if feature == null:
			push_warning("Unsupported park feature: %s" % spec.get("kind", "<missing>"))
			continue
		var feature_name := str(spec.get("name", "ParkFeature"))
		feature.name = feature_name
		feature.set_meta("route", str(spec.get("route", "mixed")))
		feature.set_meta("difficulty", str(spec.get("difficulty", "intermediate")))
		built[feature_name] = feature
	return built

static func _build_feature(parent: Node3D, spec: Dictionary, physics_profile: SkiPhysicsProfile) -> Node3D:
	var kind := str(spec.get("kind", ""))
	var label := str(spec.get("name", "ParkFeature"))
	match kind:
		"tabletop":
			return ParkLayout.add_tabletop(
				parent, label, physics_profile, float(spec.x), float(spec.z), float(spec.speed), float(spec.lip),
				float(spec.get("width", 8.5)), float(spec.get("drop", 0.0)), float(spec.get("yaw", 0.0)),
				float(spec.get("pop", physics_profile.minimum_pop_strength))
			)
		"hip":
			return ParkLayout.add_hip(
				parent, label, physics_profile, float(spec.x), float(spec.z), float(spec.speed), float(spec.lip),
				float(spec.yaw), float(spec.get("pop", physics_profile.minimum_pop_strength))
			)
		"roller":
			return ParkLayout.add_roller(
				parent, label, float(spec.x), float(spec.z), float(spec.get("length", 8.0)),
				float(spec.get("height", 0.8)), float(spec.get("width", 9.0))
			)
		"rail":
			var rail_points: Array[Vector3] = []
			for encoded: Vector3 in spec.get("points", []):
				rail_points.append(ParkLayout.rail_point(encoded.x, encoded.y, encoded.z))
			var rail := ParkLayout.add_rail(
				parent, label, rail_points, int(spec.get("rail_type", GrindRail3D.RailType.RAIL)),
				float(spec.get("radius", 0.9)), float(spec.get("friction", 0.7))
			)
			rail.approach_angle_degrees = float(spec.get("approach", 44.0))
			rail.drift_bias = float(spec.get("drift_bias", 0.0))
			ParkLayout.add_rail_contours(parent, label, rail_points)
			return rail
		"berm":
			return ParkLayout.add_berm(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.width),
				float(spec.bank), float(spec.get("yaw", 0.0))
			)
		"moguls":
			return ParkLayout.add_mogul_field(
				parent, label, float(spec.x), float(spec.z), int(spec.rows), float(spec.spacing),
				float(spec.height), float(spec.width)
			)
		"butter":
			return ParkLayout.add_butter_pad(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.width), float(spec.height)
			)
		"side_hit":
			return ParkLayout.add_side_hit(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.height),
				float(spec.width), float(spec.get("yaw", 0.0))
			)
		"wallride":
			var wall_color: Color = spec.get("color", Color("#ef8354"))
			return ParkLayout.add_wallride(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.height),
				float(spec.get("yaw", 0.0)), wall_color
			)
		"bonk":
			var bonk_color: Color = spec.get("color", Color("#ffc857"))
			return ParkLayout.add_bonk(
				parent, label, float(spec.x), float(spec.z), float(spec.height), float(spec.radius),
				bonk_color
			)
		"cannon":
			return ParkLayout.add_cannon(
				parent, label, float(spec.x), float(spec.z), float(spec.length), float(spec.width), float(spec.height)
			)
		"gate":
			var gate_color: Color = spec.get("color", Color("#55d6be"))
			return ParkLayout.add_gate(
				parent, label, float(spec.x), float(spec.z), float(spec.width),
				gate_color
			)
	return null
