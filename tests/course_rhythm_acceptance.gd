extends Node

## Phase 8 course acceptance: three-jump hero progression, recovery rhythm,
## clean center corridor, and runout.
##
## Hero identity/progression/rhythm are validated from the course data through
## the existing trajectory-aware jump_table sizing. The center corridor is
## validated against the REAL built feature geometry (world AABBs of the
## instantiated resort), so a feature that visually overhangs the hero lane
## fails even when the data looks clean.

const EXPECTED_HERO_JUMPS := ["SmallTable", "MediumTable", "LargeTable"]
const EXPECTED_CHALLENGES: Array[StringName] = [
	&"summit_grab_and_land",
	&"upper_side_hit_straight",
	&"technical_kink_clean",
	&"transfer_expert_link",
	&"lower_rainbow_grab",
	&"finale_clean_360",
]
const EXPECTED_SPOTS: Array[StringName] = [
	&"summit_fundamentals",
	&"upper_fork",
	&"technical_yard",
	&"transfer_zone",
	&"lower_hero",
	&"finale",
]
const FACE_EDGE_HALF_WIDTH := 27.0
# Action bands are samples through the jump structure itself; the free width
# must cover the jump deck (9.0/10.5/11.5 m) with a small margin. Setup and
# runout bands carry the wider "usable lane" target.
const ACTION_MIN_USABLE_WIDTH := 10.0
const SETUP_MIN_USABLE_WIDTH := 18.0
const MIN_SETUP_SLOPE_M := 55.0
const MAX_SETUP_SLOPE_M := 100.0
const MIN_RUNOUT_SLOPE_M := 60.0
const CORRIDOR_SLICE_STEP_M := 1.0

@onready var resort: Node = $Resort
var profile := ParkCourseProfile.new()
var physics_profile: SkiPhysicsProfile
var failures: Array[String] = []
var cos_pitch := cos(deg_to_rad(18.0))
var jump_data: Dictionary = {}

func _ready() -> void:
	await get_tree().process_frame
	physics_profile = load("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	_validate_hero_identity_and_progression()
	_validate_step_down_removed()
	_validate_spot_and_challenge_contract()
	_validate_spacing_and_runout()
	_validate_built_corridor()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("COURSE_RHYTHM_PASS: three-jump progression, recovery rhythm, clean center corridor, and runout validated")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("COURSE_RHYTHM_FAIL: " + failure)
	get_tree().quit(1)

func _specs_by_name() -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in profile.feature_specs():
		result[str(spec.get("name", ""))] = spec
	return result

func _validate_hero_identity_and_progression() -> void:
	var specs := _specs_by_name()
	var tablets: Array[String] = []
	for name: String in specs:
		if StringName((specs[name] as Dictionary).get("kind", &"")) == &"tabletop":
			tablets.append(name)
	tablets.sort()
	var expected_sorted := EXPECTED_HERO_JUMPS.duplicate()
	expected_sorted.sort()
	if tablets != expected_sorted:
		failures.append("Primary tabletop set is %s, expected exactly %s" % [tablets, expected_sorted])
		return
	var previous_speed := 0.0
	var previous_lip := 0.0
	var previous_width := 0.0
	var previous_range := 0.0
	var previous_x := INF
	for name: String in EXPECTED_HERO_JUMPS:
		var spec: Dictionary = specs[name]
		if not bool(spec.get("hero_feature", false)):
			failures.append("%s is not flagged as a hero feature" % name)
		var speed := float(spec.speed)
		var lip := float(spec.lip)
		var width := float(spec.width)
		var z := float(spec.z)
		var x := float(spec.x)
		var metrics := _jump_metrics(spec)
		var table_range := float(metrics.range)
		if speed <= previous_speed or lip <= previous_lip or width <= previous_width or table_range <= previous_range:
			failures.append("Jump progression is not strictly increasing at %s (speed %.1f lip %.1f width %.1f range %.1f)" % [name, speed, lip, width, table_range])
		if z >= previous_x:
			failures.append("%s does not sit downhill of the previous hero jump (z %.1f)" % [name, z])
		previous_speed = speed
		previous_lip = lip
		previous_width = width
		previous_range = table_range
		previous_x = z
		jump_data[name] = {
			"spec": spec,
			"metrics": metrics,
			"end_z": z - float(metrics.downhill_world),
			"run_in_z": z + float(metrics.run_in_world),
		}
	var speed_text := []
	var lip_text := []
	var width_text := []
	var range_text := []
	for name: String in EXPECTED_HERO_JUMPS:
		var entry: Dictionary = jump_data[name]
		speed_text.append("%.1f" % float((entry.spec as Dictionary).speed))
		lip_text.append("%.1f" % float((entry.spec as Dictionary).lip))
		width_text.append("%.1f" % float((entry.spec as Dictionary).width))
		range_text.append("%.1f" % float((entry.metrics as Dictionary).range))
	print("COURSE_HERO_SAMPLE speeds=%s lips=%s widths=%s ranges=%s" % [str(speed_text), str(lip_text), str(width_text), str(range_text)])

func _validate_step_down_removed() -> void:
	for spec: Dictionary in profile.feature_specs():
		if str(spec.get("name", "")) == "StepDownTable" or StringName(spec.get("feature_id", &"")) == &"step_down_table":
			failures.append("StepDownTable is still present in the course feature table")
	for spot: ParkSpotSpec in profile.spot_specs():
		if &"step_down_table" in spot.feature_ids:
			failures.append("Spot %s still references step_down_table" % spot.id)

func _validate_spot_and_challenge_contract() -> void:
	var errors := profile.validate_content()
	for error: String in errors:
		failures.append("course validation: " + error)
	var spots := profile.spot_specs()
	var spot_ids: Array[StringName] = []
	for spot: ParkSpotSpec in spots:
		spot_ids.append(spot.id)
		# The finale route contract must survive the StepDownTable migration.
		for route: StringName in [&"safe", &"intermediate", &"expert"]:
			if not spot.has_route(route) or spot.features_for_route(route).is_empty():
				failures.append("%s lost its feature-backed %s route" % [spot.id, route])
	if spot_ids != EXPECTED_SPOTS:
		failures.append("Stable spot IDs changed: %s" % str(spot_ids))
	var challenge_ids: Array[StringName] = []
	for challenge: ParkChallengeSpec in profile.challenge_specs():
		challenge_ids.append(challenge.id)
	if challenge_ids != EXPECTED_CHALLENGES:
		failures.append("Stable challenge IDs changed: %s" % str(challenge_ids))

func _validate_spacing_and_runout() -> void:
	var finish_z := profile.finish_trigger_world_z()
	var small: Dictionary = jump_data.get("SmallTable", {})
	var medium: Dictionary = jump_data.get("MediumTable", {})
	var large: Dictionary = jump_data.get("LargeTable", {})
	if small.is_empty() or medium.is_empty() or large.is_empty():
		return
	var clean_1 := (float(small.end_z) - float(medium.run_in_z)) / cos_pitch
	var clean_2 := (float(medium.end_z) - float(large.run_in_z)) / cos_pitch
	var runout := (float(large.end_z) - finish_z) / cos_pitch
	print("COURSE_RHYTHM_SAMPLE recovery_1=%.1f m recovery_2=%.1f m runout=%.1f m finish_z=%.1f" % [clean_1, clean_2, runout, finish_z])
	for gap: Array in [[clean_1, "Recovery 1"], [clean_2, "Recovery 2"]]:
		var value := float(gap[0])
		if value < MIN_SETUP_SLOPE_M or value > MAX_SETUP_SLOPE_M:
			failures.append("%s clean setup is %.1f slope m (need %.0f-%.0f)" % [gap[1], value, MIN_SETUP_SLOPE_M, MAX_SETUP_SLOPE_M])
	if runout < MIN_RUNOUT_SLOPE_M:
		failures.append("Final runout is %.1f slope m (need at least %.0f)" % [runout, MIN_RUNOUT_SLOPE_M])
	var face_half := ParkLayout.face_half_world_z()
	if face_half < absf(finish_z) + 10.0:
		failures.append("Face extent %.1f does not cover the finish %.1f with margin" % [face_half, finish_z])
	var drop_in := (profile.spawn_world_z() - float(small.run_in_z)) / cos_pitch
	print("COURSE_RHYTHM_SAMPLE drop_in=%.1f m face_half=%.1f m" % [drop_in, face_half])

func _validate_built_corridor() -> void:
	if resort == null:
		failures.append("Resort instance is missing")
		return
	var features: Dictionary = resort.course_features
	if features == null or features.is_empty():
		failures.append("Resort did not build course features")
		return
	var specs := _specs_by_name()
	var hero_x := float((specs["SmallTable"] as Dictionary).x)
	for name: String in EXPECTED_HERO_JUMPS:
		if absf(float((specs[name] as Dictionary).x) - hero_x) > 0.001:
			failures.append("%s is not on the shared hero lane x=%.1f" % [name, hero_x])
	var boxes: Dictionary = {}
	for name: String in features:
		var node := features[name] as Node3D
		if node == null:
			continue
		var bounds := _feature_aabb(node)
		if bool(bounds.get("valid", false)):
			boxes[name] = bounds.get("box", AABB())
	var small: Dictionary = jump_data.get("SmallTable", {})
	var medium: Dictionary = jump_data.get("MediumTable", {})
	var large: Dictionary = jump_data.get("LargeTable", {})
	if small.is_empty() or medium.is_empty() or large.is_empty():
		return
	var bands: Array[Dictionary] = [
		{"label": "drop_in", "z_max": profile.spawn_world_z(), "z_min": float(small.run_in_z), "min_width": SETUP_MIN_USABLE_WIDTH},
		{"label": "jump_1_action", "z_max": float(small.spec.z), "z_min": float(small.end_z), "min_width": ACTION_MIN_USABLE_WIDTH},
		{"label": "recovery_1", "z_max": float(small.end_z), "z_min": float(medium.run_in_z), "min_width": SETUP_MIN_USABLE_WIDTH},
		{"label": "jump_2_action", "z_max": float(medium.spec.z), "z_min": float(medium.end_z), "min_width": ACTION_MIN_USABLE_WIDTH},
		{"label": "recovery_2", "z_max": float(medium.end_z), "z_min": float(large.run_in_z), "min_width": SETUP_MIN_USABLE_WIDTH},
		{"label": "jump_3_action", "z_max": float(large.spec.z), "z_min": float(large.end_z), "min_width": ACTION_MIN_USABLE_WIDTH},
		{"label": "runout", "z_max": float(large.end_z), "z_min": profile.finish_trigger_world_z(), "min_width": SETUP_MIN_USABLE_WIDTH},
	]
	for band: Dictionary in bands:
		var label := str(band.label)
		var z_max := float(band.z_max)
		var z_min := float(band.z_min)
		# Slice the band so obstacles only constrain the z-slices they really
		# occupy (a world AABB spans the feature's full width even where the
		# built profile is narrower at that z).
		var min_usable := INF
		var min_usable_z := z_min
		var blockers: Dictionary = {}
		var z := z_min
		while z <= z_max + 0.001:
			var left := -FACE_EDGE_HALF_WIDTH
			var right := FACE_EDGE_HALF_WIDTH
			for name: String in boxes:
				if name in EXPECTED_HERO_JUMPS:
					continue
				var spec: Dictionary = specs.get(name, {})
				if StringName(spec.get("kind", &"")) == &"gate":
					continue
				var box: AABB = boxes[name]
				if box.end.z < z or box.position.z > z:
					continue
				if box.position.x <= hero_x and hero_x <= box.end.x:
					blockers[name] = true
					continue
				if box.position.x > hero_x:
					right = minf(right, box.position.x)
				else:
					left = maxf(left, box.end.x)
			var usable := right - left
			if usable < min_usable:
				min_usable = usable
				min_usable_z = z
			z += CORRIDOR_SLICE_STEP_M
		print("COURSE_CORRIDOR_SAMPLE %s usable=%.1f m at z=%.1f" % [label, min_usable, min_usable_z])
		for blocker: String in blockers:
			failures.append("%s blocks the hero lane during %s" % [blocker, label])
		if min_usable < float(band.min_width):
			failures.append("%s usable lane is %.1f m (need %.0f)" % [label, min_usable, float(band.min_width)])

func _jump_metrics(spec: Dictionary) -> Dictionary:
	var sizing: Dictionary = ParkLayout.jump_table(
		physics_profile,
		float(spec.get("speed", 15.0)),
		float(spec.get("lip", 7.0)),
		float(spec.get("drop", 0.0)),
		float(spec.get("pop", physics_profile.minimum_pop_strength))
	)
	var lip_length := float(sizing.get("lip_length", 9.0))
	var table_length := float(sizing.get("table_length", 10.0))
	var landing_length := float(sizing.get("landing_length", 8.0))
	var run_in := clampf(lip_length * 0.68, 4.5, 7.5)
	var run_out := clampf(landing_length * 0.28, 3.5, 6.0)
	var downhill_slope := lip_length + table_length + ParkLayout.TABLE_LANDING_SEAM_M + landing_length + run_out
	return {
		"range": float(sizing.get("range", 15.0)),
		"downhill_slope": downhill_slope,
		"downhill_world": downhill_slope * cos_pitch,
		"run_in_world": run_in * cos_pitch,
		"run_out": run_out,
	}

func _feature_aabb(node: Node3D) -> Dictionary:
	var result := AABB()
	var initialized := false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var world: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		result = world if not initialized else result.merge(world)
		initialized = true
	return {"valid": initialized, "box": result}
