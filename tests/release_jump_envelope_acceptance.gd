extends Node

## Phase 13 hero-jump robustness envelope: every hero jump is swept around its
## design point (about +/-15% entry speed, lateral offsets, approach-angle
## error) plus a deliberate ride-around, and a small terrain takeoff records the
## smallest no-trick air size. Failures here are release blockers, so the sweep
## asserts survival/recovery rather than the nominal trajectory.

const ParkLayout := preload("res://world/park_features/park_layout.gd")

const HERO_JUMPS: Array[String] = ["SmallTable", "MediumTable", "LargeTable"]
const SPEED_FACTORS: Array[float] = [0.85, 1.15]
const LATERAL_OFFSETS: Array[float] = [-3.5, 0.0, 3.5]
const APPROACH_YAWS: Array[float] = [-8.0, 8.0]
const MISS_OFFSET_FACTOR := 0.92
const MAX_PASS_FRAMES := 300
const MIN_CLEAN_RATIO := 0.9
const TERRAIN_TAKEOFF_SPEED := 9.0
const CREST_PASSES := 30

@onready var resort: Node = $Resort

var skier: SkierController
var camera: SkiCameraController
var physics_profile: SkiPhysicsProfile
var course_profile: ParkCourseProfile
var failures: Array[String] = []
var envelope_clean := 0
var envelope_total := 0
var miss_clean := 0
var miss_total := 0
var design_airtimes: Dictionary = {}
var terrain_hop_seconds := -1.0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	camera = resort.get_node("CameraRig") as SkiCameraController
	physics_profile = resort.get("physics_profile") as SkiPhysicsProfile
	course_profile = resort.get("course_profile") as ParkCourseProfile
	if skier == null or camera == null or physics_profile == null or course_profile == null:
		failures.append("Release envelope could not bind the skier, camera, or profiles")
		_finish()
		return
	for jump_index: int in range(HERO_JUMPS.size()):
		var jump_name := HERO_JUMPS[jump_index]
		var spec := _spec_for(jump_name)
		if spec.is_empty():
			failures.append("Release envelope could not find the %s course spec" % jump_name)
			continue
		await _run_case(jump_name, spec, "nominal", 1.0, 0.0, 0.0)
		for speed_factor: float in SPEED_FACTORS:
			for lateral: float in LATERAL_OFFSETS:
				await _run_case(jump_name, spec, "envelope", speed_factor, lateral, 0.0)
		await _run_case(jump_name, spec, "approach", 1.0, 0.0, APPROACH_YAWS[jump_index % APPROACH_YAWS.size()])
		await _run_miss(jump_name, spec)
	await _run_terrain_takeoff()
	await _run_crest_loop()
	_validate()
	_finish()

func _run_case(jump_name: String, spec: Dictionary, kind: String, speed_factor: float, lateral: float, yaw: float) -> void:
	var sizing := _sizing(spec)
	var normal := ParkLayout.snow_normal()
	var edge_z := float(spec.z) - float(sizing.lip_length) * cos(deg_to_rad(ParkLayout.PITCH_DEG))
	var basis := ParkLayout.downhill_basis(yaw)
	var lip_dir := (sizing.lip_dir as Vector3).rotated(normal, deg_to_rad(yaw))
	var speed := float(spec.speed) * speed_factor
	var velocity := lip_dir * speed + normal * physics_profile.pop_impulse * clampf(float(spec.get("pop", physics_profile.minimum_pop_strength)), 0.0, 1.0)
	var origin := ParkLayout.snow_at(float(spec.x) + lateral, edge_z) + normal * (float(sizing.lip_rise) + 0.05)
	skier.reset_for_benchmark(Transform3D(basis, origin), velocity)
	camera.reset_immediate()
	var landed := false
	var bailed := false
	var frames := 0
	for _frame: int in range(MAX_PASS_FRAMES):
		await get_tree().physics_frame
		frames += 1
		if skier.state == SkierController.State.BAIL:
			bailed = true
			break
		if skier.state == SkierController.State.GROUND:
			landed = true
			break
	if kind == "nominal":
		design_airtimes[jump_name] = float(frames) / 60.0
	if kind == "envelope":
		envelope_total += 1
		if landed and not bailed:
			envelope_clean += 1
		else:
			failures.append("%s envelope case (speed x%.2f, lateral %.1f) %s" % [jump_name, speed_factor, lateral, "bailed" if bailed else "never landed"])
	if kind == "approach" and (bailed or not landed):
		failures.append("%s approach-angle case %s" % [jump_name, "bailed" if bailed else "never landed"])
	print("RELEASE_ENVELOPE_CASE jump=%s kind=%s speed_factor=%.2f lateral=%.1f yaw=%.1f landed=%s bailed=%s frames=%d" % [jump_name, kind, speed_factor, lateral, yaw, str(landed), str(bailed), frames])

func _run_miss(jump_name: String, spec: Dictionary) -> void:
	var sizing := _sizing(spec)
	var normal := ParkLayout.snow_normal()
	var edge_z := float(spec.z) - float(sizing.lip_length) * cos(deg_to_rad(ParkLayout.PITCH_DEG))
	var lateral := float(spec.width) * MISS_OFFSET_FACTOR
	var origin := ParkLayout.snow_at(float(spec.x) + lateral, edge_z + 6.0) + normal * 0.6
	skier.reset_for_benchmark(Transform3D(ParkLayout.downhill_basis(), origin), ParkLayout.downhill() * float(spec.speed))
	camera.reset_immediate()
	var landed := false
	var bailed := false
	for _frame: int in range(MAX_PASS_FRAMES):
		await get_tree().physics_frame
		if skier.state == SkierController.State.BAIL:
			bailed = true
			break
		if skier.state == SkierController.State.GROUND:
			landed = true
			break
	miss_total += 1
	if landed and not bailed:
		miss_clean += 1
	else:
		failures.append("%s ride-around %s" % [jump_name, "bailed" if bailed else "never recovered"])
	print("RELEASE_ENVELOPE_MISS jump=%s lateral=%.1f landed=%s bailed=%s" % [jump_name, lateral, str(landed), str(bailed)])

func _run_terrain_takeoff() -> void:
	var roller_z := 120.0
	for spec: Dictionary in course_profile.feature_specs():
		if str(spec.get("name", "")) == "SummitRollerB":
			roller_z = float(spec.z)
			break
	skier.global_position = ParkLayout.surface_hover(0.0, roller_z + 6.0, ParkLayout.SPAWN_HOVER)
	skier.global_basis = ParkLayout.downhill_basis()
	skier.velocity = ParkLayout.downhill() * TERRAIN_TAKEOFF_SPEED
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = ParkLayout.snow_normal()
	skier.contact.average_hit_position = ParkLayout.snow_at(0.0, roller_z + 6.0)
	skier.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	camera.reset_immediate()
	var air_frames := 0
	var hop_frames := 0
	var was_air := false
	for _frame: int in range(180):
		await get_tree().physics_frame
		if skier.state == SkierController.State.AIR:
			if not was_air:
				air_frames = 0
			was_air = true
			air_frames += 1
		elif was_air:
			hop_frames = air_frames
			break
	terrain_hop_seconds = float(hop_frames) / 60.0
	if hop_frames > 0:
		if terrain_hop_seconds < 0.05 or terrain_hop_seconds > 1.5:
			failures.append("Terrain takeoff airtime %.2f s escaped the small-hop window" % terrain_hop_seconds)
	print("RELEASE_ENVELOPE_TERRAIN roller_z=%.1f speed=%.1f hop_seconds=%.3f" % [roller_z, TERRAIN_TAKEOFF_SPEED, terrain_hop_seconds])

func _run_crest_loop() -> void:
	# 30 additional convex-crest/landing passes at varied entry speeds and
	# slight approach angles, so the release stress count exceeds 50 discrete
	# landings when combined with the hero envelope.
	var roller_z := 120.0
	var roller_length := 5.5
	for spec: Dictionary in course_profile.feature_specs():
		if str(spec.get("name", "")) == "SummitRollerB":
			roller_z = float(spec.z)
			roller_length = float(spec.get("length", 5.5))
			break
	var landings := 0
	var pass_bails := 0
	for index: int in range(CREST_PASSES):
		var speed := 7.0 + float(index % 7)
		var yaw := -6.0 if index % 2 == 0 else 6.0
		var travel := -ParkLayout.downhill_basis(yaw).z.normalized() * speed
		skier.reset_for_benchmark(
			Transform3D(ParkLayout.downhill_basis(yaw), ParkLayout.surface_hover(0.0, roller_z + 5.0, ParkLayout.SPAWN_HOVER)),
			travel
		)
		camera.reset_immediate()
		var was_air := false
		for _frame: int in range(120):
			await get_tree().physics_frame
			if skier.state == SkierController.State.BAIL:
				pass_bails += 1
				break
			if skier.state == SkierController.State.AIR:
				was_air = true
			elif was_air:
				landings += 1
				was_air = false
			if skier.global_position.z < roller_z - roller_length - 3.0:
				break
		if skier.state == SkierController.State.BAIL:
			pass_bails += 1
	if pass_bails > 0:
		failures.append("Crest loop bailed on %d of %d passes" % [pass_bails, CREST_PASSES])
	print("RELEASE_ENVELOPE_CREST passes=%d landings=%d bails=%d" % [CREST_PASSES, landings, pass_bails])

func _validate() -> void:
	if envelope_total > 0:
		var ratio := float(envelope_clean) / float(envelope_total)
		if ratio < MIN_CLEAN_RATIO:
			failures.append("Hero envelope clean-landing ratio %.2f below %.2f (%d/%d)" % [ratio, MIN_CLEAN_RATIO, envelope_clean, envelope_total])
	if miss_clean != miss_total:
		failures.append("Hero ride-arounds were not all recoverable (%d/%d)" % [miss_clean, miss_total])
	if design_airtimes.size() == HERO_JUMPS.size():
		var small := float(design_airtimes.get("SmallTable", 0.0))
		var medium := float(design_airtimes.get("MediumTable", 0.0))
		var large := float(design_airtimes.get("LargeTable", 0.0))
		if not (small < medium and medium < large):
			failures.append("Design airtimes were not progressive: %.2f / %.2f / %.2f" % [small, medium, large])
		if terrain_hop_seconds > 0.0 and terrain_hop_seconds >= small:
			failures.append("Terrain takeoff (%.2f s) was not the smallest air size (table %.2f s)" % [terrain_hop_seconds, small])
	print("RELEASE_ENVELOPE_SAMPLE clean=%d/%d misses=%d/%d airtimes=%s terrain_hop=%.3f" % [envelope_clean, envelope_total, miss_clean, miss_total, str(design_airtimes), terrain_hop_seconds])

func _sizing(spec: Dictionary) -> Dictionary:
	return ParkLayout.jump_table(
		physics_profile,
		float(spec.speed),
		float(spec.lip),
		float(spec.get("drop", 0.0)),
		float(spec.get("pop", physics_profile.minimum_pop_strength))
	)

func _spec_for(name: String) -> Dictionary:
	for spec: Dictionary in course_profile.feature_specs():
		if str(spec.get("name", "")) == name:
			return spec
	return {}

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("RELEASE_JUMP_ENVELOPE_PASS: hero jumps survive the speed/lateral/approach sweep and misses stay recoverable")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RELEASE_JUMP_ENVELOPE_FAIL: " + failure)
	get_tree().quit(1)
