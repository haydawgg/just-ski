extends Node

## Phase 9 terrain continuity acceptance.
##
## Validates three contracts against the real built resort:
## 1. Hero jump centerlines are continuous from run-in through the table/landing
##    seam to the runout (no slot, trench, or step at the knuckle).
## 2. Feature bases are blended into the piste by deterministic render-only
##    aprons, and the profiled bodies keep their authored surface kinds.
## 3. The presentation-only summit heightfield stays coplanar with gameplay
##    collision across the full usable corridor, and the chase camera does not
##    dip into the presentation shoulder relief.

const ParkLayout := preload("res://world/park_features/park_layout.gd")
const SnowSurface := preload("res://world/snow_material.gd")
const SummitEnvironmentBuilderModule := preload("res://world/summit_environment_builder.gd")

const HERO_JUMPS: Array[String] = ["SmallTable", "MediumTable", "LargeTable"]
const APRON_KINDS: Array[String] = ["tabletop", "hip", "roller", "butter", "side_hit"]
const CORRIDOR_HALF_WIDTH := 27.0
const CORRIDOR_TOLERANCE_M := 0.003
const CORRIDOR_STEP_M := 2.0
const APRON_REACH_MIN_M := 0.8
const APRON_MAX_HEIGHT_M := 0.05
const APRON_MIN_OFFSET_M := 0.0015
const CENTERLINE_STEP_M := 0.25
const CENTERLINE_STEP_LIMIT_M := 0.06
const SEAM_PROBE_STEP_M := 0.1
const SEAM_PROBE_HALF_M := 0.6
const SEAM_DROP_LIMIT_M := 0.02
const CAMERA_CLEARANCE_MIN_M := 0.25
const CAMERA_EDGE_X := 26.5

@onready var resort: Node3D = $Resort

var failures: Array[String] = []
var profile: ParkCourseProfile
var physics_profile: SkiPhysicsProfile

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	physics_profile = load("res://resources/physics/default_ski_profile.tres") as SkiPhysicsProfile
	profile = resort.get("course_profile") as ParkCourseProfile
	if profile == null:
		failures.append("Resort did not expose a course profile")
		_finish()
		return
	_validate_jump_centerline()
	_validate_surface_kinds()
	_validate_feature_aprons()
	_validate_summit_corridor()
	_validate_camera_clearance()
	_finish()

func _validate_jump_centerline() -> void:
	var features: Dictionary = resort.course_features
	for name: String in HERO_JUMPS:
		var spec := _spec_for(name)
		var root := features.get(name) as Node3D
		if root == null or spec.is_empty():
			failures.append("%s was not built from an authored spec" % name)
			continue
		var sizing := ParkLayout.jump_table(
			physics_profile,
			float(spec.speed),
			float(spec.lip),
			float(spec.get("drop", 0.0)),
			float(spec.get("pop", physics_profile.minimum_pop_strength))
		)
		var lip_length := float(sizing.lip_length)
		var table_length := float(sizing.table_length)
		var landing_length := float(sizing.landing_length)
		var run_in := clampf(lip_length * 0.68, 4.5, 7.5)
		var run_out := clampf(landing_length * 0.28, 3.5, 6.0)
		var total := lip_length + table_length + ParkLayout.TABLE_LANDING_SEAM_M + landing_length + run_out
		var x := float(spec.x)
		var lip_start := ParkLayout.snow_at(x, float(spec.z))
		var down := ParkLayout.downhill()
		var previous_delta := INF
		var maximum_step := 0.0
		var d := -run_in
		while d <= total + 0.001:
			var point := lip_start + down * d
			var delta := _surface_delta(point)
			if not is_finite(delta):
				failures.append("%s centerline had no collision surface at %.2f m (z %.1f)" % [name, d, point.z])
			else:
				if delta < -0.02:
					failures.append("%s centerline dropped %.3f m below the piste at %.2f m" % [name, delta, d])
				if is_finite(previous_delta):
					maximum_step = maxf(maximum_step, absf(delta - previous_delta))
				previous_delta = delta
			d += CENTERLINE_STEP_M
		# Fine probe across the table -> landing junction; the old 0.25 m slot
		# exposed the buried piste and must never reappear.
		var seam_d := lip_length + table_length
		var seam_previous := INF
		var seam_drop := 0.0
		var seam_step := 0.0
		var s := seam_d - SEAM_PROBE_HALF_M
		while s <= seam_d + SEAM_PROBE_HALF_M + 0.001:
			var point := lip_start + down * s
			var delta := _surface_delta(point)
			if not is_finite(delta):
				failures.append("%s seam had no collision surface at %.2f m" % [name, s])
			else:
				if is_finite(seam_previous):
					seam_drop = maxf(seam_drop, seam_previous - delta)
					seam_step = maxf(seam_step, absf(delta - seam_previous))
				seam_previous = delta
			s += SEAM_PROBE_STEP_M
		print("TERRAIN_CENTERLINE_SAMPLE jump=%s max_step=%.4f seam_step=%.4f seam_drop=%.4f" % [name, maximum_step, seam_step, seam_drop])
		if maximum_step > CENTERLINE_STEP_LIMIT_M:
			failures.append("%s centerline stepped %.3f m between 0.25 m samples (limit %.2f)" % [name, maximum_step, CENTERLINE_STEP_LIMIT_M])
		if seam_drop > SEAM_DROP_LIMIT_M:
			failures.append("%s table/landing seam dropped %.3f m (limit %.2f)" % [name, seam_drop, SEAM_DROP_LIMIT_M])

func _validate_surface_kinds() -> void:
	var features: Dictionary = resort.course_features
	for name: String in HERO_JUMPS:
		var root := features.get(name) as Node3D
		if root == null:
			continue
		var table := root.get_node_or_null("Table") as StaticBody3D
		var landing := root.get_node_or_null("Landing") as StaticBody3D
		if table == null or landing == null:
			failures.append("%s lost its separate Table/Landing bodies" % name)
			continue
		if int(table.get_meta("ski_surface_kind", -1)) != SnowSurface.Kind.GROOMED:
			failures.append("%s deck surface kind is no longer GROOMED" % name)
		if int(landing.get_meta("ski_surface_kind", -1)) != SnowSurface.Kind.PACKED:
			failures.append("%s landing surface kind is no longer PACKED" % name)

func _validate_feature_aprons() -> void:
	var specs := _specs_by_name()
	var features: Dictionary = resort.course_features
	var checked := 0
	for feature_name: String in features:
		var spec: Dictionary = specs.get(feature_name, {})
		if str(spec.get("kind", "")) not in APRON_KINDS:
			continue
		var root := features[feature_name] as Node3D
		if root == null:
			continue
		checked += 1
		var feature_min := Vector3(INF, INF, INF)
		var feature_max := Vector3(-INF, -INF, -INF)
		var apron_min := Vector3(INF, INF, INF)
		var apron_max := Vector3(-INF, -INF, -INF)
		var apron_count := 0
		for mesh_node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var bounds := _mesh_world_aabb(mesh_instance)
			if bool(mesh_instance.get_meta("apron_segment", false)):
				apron_count += 1
				apron_min = apron_min.min(bounds.position)
				apron_max = apron_max.max(bounds.end)
				if not mesh_instance.find_children("*", "CollisionShape3D", true, false).is_empty():
					failures.append("%s apron introduced collision" % feature_name)
				var height_limit := APRON_MAX_HEIGHT_M
				if str(spec.get("kind", "")) == "butter":
					# The butter cap rides the authored box top; only its outer
					# ring feathers down to the piste.
					height_limit = maxf(float(spec.get("height", 0.08)), 0.08) + 0.01
				_validate_apron_heights(feature_name, mesh_instance, height_limit)
			else:
				feature_min = feature_min.min(bounds.position)
				feature_max = feature_max.max(bounds.end)
		if apron_count == 0:
			failures.append("%s has no base apron" % feature_name)
			continue
		var lateral_reach := maxf(feature_min.x - apron_min.x, apron_max.x - feature_max.x)
		if lateral_reach < APRON_REACH_MIN_M - 0.01:
			failures.append("%s apron only reaches %.2f m beyond the base (need %.2f)" % [feature_name, lateral_reach, APRON_REACH_MIN_M])
	print("TERRAIN_APRON_SAMPLE features=%d" % checked)

func _validate_apron_heights(feature_name: String, apron: MeshInstance3D, height_limit: float) -> void:
	var mesh := apron.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		failures.append("%s apron produced no render surface" % feature_name)
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var snow_normal := ParkLayout.snow_normal()
	var maximum_height := -INF
	var minimum_height := INF
	var minimum_world := Vector3.ZERO
	var minimum_normal := Vector3.ZERO
	for index: int in range(vertices.size()):
		if normals[index].dot(snow_normal) <= 0.3:
			continue
		var world := apron.global_transform * vertices[index]
		var height := world.y - ParkLayout.snow_at(world.x, world.z).y
		if height < minimum_height:
			minimum_height = height
			minimum_world = world
			minimum_normal = normals[index]
		maximum_height = maxf(maximum_height, height)
	if not is_finite(maximum_height) or not is_finite(minimum_height):
		failures.append("%s apron exposed no upward-facing vertices" % feature_name)
		return
	if maximum_height > height_limit + 0.001:
		failures.append("%s apron rises %.3f m above the piste (limit %.2f)" % [feature_name, maximum_height, height_limit])
	if minimum_height < APRON_MIN_OFFSET_M - 0.001:
		failures.append("%s apron sits %.4f m from the piste at %s normal=%s (z-fight risk)" % [feature_name, minimum_height, minimum_world, minimum_normal])

func _validate_summit_corridor() -> void:
	var summit_profile := resort.get("summit_environment_profile") as SummitEnvironmentProfile
	if summit_profile == null or not summit_profile.enabled:
		failures.append("Summit presentation profile was unavailable")
		return
	if summit_profile.playable_half_width_m + 0.001 < CORRIDOR_HALF_WIDTH:
		failures.append("Summit playable corridor %.1f m is narrower than the usable lane %.1f m" % [summit_profile.playable_half_width_m, CORRIDOR_HALF_WIDTH])
	var finish_z := profile.finish_trigger_world_z()
	var z := finish_z - 10.0
	var worst_delta := 0.0
	var worst_info := ""
	while z <= profile.spawn_world_z() + 10.0:
		var x := -CORRIDOR_HALF_WIDTH
		while x <= CORRIDOR_HALF_WIDTH + 0.001:
			var expected := ParkLayout.snow_at(x, z).y + summit_profile.surface_offset_m
			var actual := SummitEnvironmentBuilderModule.sample_height(x, z, summit_profile)
			var delta := absf(actual - expected)
			if delta > worst_delta:
				worst_delta = delta
				worst_info = "(%.1f, %.1f)" % [x, z]
			x += CORRIDOR_STEP_M
		z += CORRIDOR_STEP_M
	print("TERRAIN_CORRIDOR_SAMPLE max_delta=%.4f at %s" % [worst_delta, worst_info])
	if worst_delta > CORRIDOR_TOLERANCE_M:
		failures.append("Summit render surface diverged %.4f m from collision inside the corridor at %s" % [worst_delta, worst_info])

func _validate_camera_clearance() -> void:
	var skier := resort.get_node_or_null("Skier") as SkierController
	var camera := resort.get_node_or_null("CameraRig") as SkiCameraController
	var summit_profile := resort.get("summit_environment_profile") as SummitEnvironmentProfile
	if skier == null or camera == null or camera.camera == null or summit_profile == null:
		failures.append("Camera clearance audit could not run")
		return
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	var minimum := INF
	var minimum_info := ""
	for z: float in [110.0, 12.0, -106.0, -180.0]:
		for x: float in [CAMERA_EDGE_X, 0.0, -CAMERA_EDGE_X]:
			for yaw: float in [0.0, 25.0, -25.0, 55.0, -55.0, 80.0, -80.0]:
				skier.global_position = ParkLayout.surface_hover(x, z, ParkLayout.SPAWN_HOVER)
				skier.global_basis = ParkLayout.downhill_basis(yaw)
				skier.velocity = ParkLayout.downhill() * 12.0
				skier.state = SkierController.State.GROUND
				skier.contact.grounded = true
				skier.contact.average_normal = ParkLayout.snow_normal()
				skier.contact.average_hit_position = ParkLayout.snow_at(x, z)
				camera.reset_immediate()
				var camera_position := camera.global_position
				var render_height := SummitEnvironmentBuilderModule.sample_height(camera_position.x, camera_position.z, summit_profile)
				var clearance := camera_position.y - render_height
				if clearance < minimum:
					minimum = clearance
					minimum_info = "skier=(%.1f,%.1f) yaw=%.0f camera=(%.1f,%.1f,%.1f)" % [x, z, yaw, camera_position.x, camera_position.y, camera_position.z]
	print("TERRAIN_CAMERA_SAMPLE min_clearance=%.3f %s" % [minimum, minimum_info])
	if minimum < CAMERA_CLEARANCE_MIN_M:
		failures.append("Camera dipped %.3f m below the presentation snow at %s" % [minimum, minimum_info])

func _surface_delta(point: Vector3) -> float:
	var normal := ParkLayout.snow_normal()
	var query := PhysicsRayQueryParameters3D.create(point + normal * 2.5, point - normal * 1.5, 1)
	var skier := resort.get_node_or_null("Skier")
	if skier is CollisionObject3D:
		query.exclude = [(skier as CollisionObject3D).get_rid()]
	var hit := resort.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return float((hit.position as Vector3).y) - ParkLayout.snow_at(point.x, point.z).y

func _mesh_world_aabb(mesh_instance: MeshInstance3D) -> AABB:
	return mesh_instance.global_transform * mesh_instance.mesh.get_aabb()

func _spec_for(name: String) -> Dictionary:
	for spec: Dictionary in profile.feature_specs():
		if str(spec.get("name", "")) == name:
			return spec
	return {}

func _specs_by_name() -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in profile.feature_specs():
		result[str(spec.get("name", ""))] = spec
	return result

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("TERRAIN_CONTINUITY_PASS: hero seams, base aprons, summit corridor correspondence, and camera clearance validated")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("TERRAIN_CONTINUITY_FAIL: " + failure)
	get_tree().quit(1)
