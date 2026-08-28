extends Node3D

const MAP_WIDTH := 57
const MAP_DEPTH := 281
const CELL_SIZE := 0.5
const START_Z := 54.0
const END_Z := -68.0
const MAX_FRAMES := 2400

var skier: SkierController
var camera: Camera3D
var frame_count := 0
var failures: Array[String] = []
var sections_seen: Dictionary = {}
var speed_bands_seen := {"low": false, "medium": false, "high": false}
var maximum_gap := 0.0
var maximum_side_difference := 0.0
var maximum_compression := 0.0
var maximum_pelvis_offset := 0.0
var maximum_normal_angle := 0.0
var grounded_samples := 0
var terrain_samples := 0
var turn_sign_changes := 0
var previous_turn_sign := 0.0
var airborne_frames := 0
var air_release_seen := false
var maximum_ski_orientation_delta := 0.0
var maximum_pelvis_correction_delta := 0.0
var maximum_leg_compression_delta := 0.0
var maximum_contact_confidence_delta := 0.0
var maximum_influence_delta := 0.0
var previous_left_ski_rotation := Vector3.ZERO
var previous_right_ski_rotation := Vector3.ZERO
var previous_pelvis_correction := 0.0
var previous_left_compression := 0.0
var previous_right_compression := 0.0
var previous_left_confidence := 0.0
var previous_right_confidence := 0.0
var previous_correction_influence := 0.0
var robustness_metrics_started := false
var awkward_confidence_reduced := false
var confidence_recovered := false
var awkward_carve_preserved := false
var knee_inversion_seen := false
var skeleton_explosion_seen := false
var minimum_awkward_confidence := 1.0
var minimum_awkward_correction := 1.0

func _ready() -> void:
	_run_synthetic_suspension_checks()
	_build_course()
	_build_skier()
	_build_camera()

func _physics_process(_delta: float) -> void:
	frame_count += 1
	_drive_linked_turns()
	if skier == null:
		return
	var debug := skier.animation_controller.debug_snapshot()
	var speed := skier.velocity.length()
	var section := _section_name(skier.global_position.z)
	sections_seen[section] = true
	_record_robustness_metrics(debug, section)
	if speed < 8.0:
		speed_bands_seen.low = true
	elif speed < 12.5:
		speed_bands_seen.medium = true
	else:
		speed_bands_seen.high = true
	if skier.state == SkierController.State.GROUND and skier.contact.grounded:
		grounded_samples += 1
		var influence := float(debug.terrain_influence)
		if influence > 0.5:
			terrain_samples += 1
		var left_gap := absf(float(debug.left_gap))
		var right_gap := absf(float(debug.right_gap))
		maximum_gap = maxf(maximum_gap, maxf(left_gap, right_gap))
		maximum_side_difference = maxf(maximum_side_difference, absf(float(debug.left_gap) - float(debug.right_gap)))
		maximum_compression = maxf(maximum_compression, maxf(absf(float(debug.left_leg_compression)), absf(float(debug.right_leg_compression))))
		maximum_pelvis_offset = maxf(maximum_pelvis_offset, absf(float(debug.terrain_pelvis_offset)))
		var left_angles := debug.left_terrain_angles as Vector2
		var right_angles := debug.right_terrain_angles as Vector2
		maximum_normal_angle = maxf(maximum_normal_angle, maxf(left_angles.length(), right_angles.length()))
		airborne_frames = 0
	else:
		airborne_frames += 1
		if airborne_frames >= 24 and float(debug.terrain_influence) < 0.2:
			air_release_seen = true
	var turn_sign := signf(skier.edge_amount) if absf(skier.edge_amount) > 0.08 else 0.0
	if turn_sign != 0.0 and previous_turn_sign != 0.0 and turn_sign != previous_turn_sign:
		turn_sign_changes += 1
	if turn_sign != 0.0:
		previous_turn_sign = turn_sign
	if frame_count % 120 == 0:
		print("TERRAIN_SUSPENSION_SAMPLE frame=%d section=%s speed=%.1f gaps=(%.3f, %.3f) compression=(%.2f, %.2f) pelvis=%.3f influence=%.2f correction=%.2f confidence=(%.2f, %.2f)" % [
			frame_count,
			section,
			speed,
			float(debug.left_gap),
			float(debug.right_gap),
			float(debug.left_leg_compression),
			float(debug.right_leg_compression),
			float(debug.terrain_pelvis_offset),
			float(debug.terrain_influence),
			float(debug.terrain_correction_influence),
			float(debug.left_contact_confidence),
			float(debug.right_contact_confidence),
		])
	if skier.global_position.z <= END_Z or frame_count >= MAX_FRAMES:
		_finish()

func _process(delta: float) -> void:
	if camera == null or skier == null:
		return
	var desired := skier.global_position + Vector3(3.6, 2.35, 5.6)
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-4.5 * delta))
	camera.look_at(skier.global_position + Vector3.UP * 0.9, Vector3.UP)

func _record_robustness_metrics(debug: Dictionary, section: String) -> void:
	var left_ski_rotation := debug.left_ski_rotation as Vector3
	var right_ski_rotation := debug.right_ski_rotation as Vector3
	var pelvis_correction := float(debug.terrain_pelvis_offset)
	var left_compression := float(debug.left_leg_compression)
	var right_compression := float(debug.right_leg_compression)
	var left_confidence := float(debug.left_contact_confidence)
	var right_confidence := float(debug.right_contact_confidence)
	var correction_influence := float(debug.terrain_correction_influence)
	if not _finite_vector(left_ski_rotation) or not _finite_vector(right_ski_rotation) or not is_finite(pelvis_correction):
		skeleton_explosion_seen = true
	if float((debug.left_knee_rotation as Vector3).x) < -0.01 or float((debug.right_knee_rotation as Vector3).x) < -0.01:
		knee_inversion_seen = true
	if robustness_metrics_started:
		maximum_ski_orientation_delta = maxf(maximum_ski_orientation_delta, maxf(
			_euler_delta_length(left_ski_rotation, previous_left_ski_rotation),
			_euler_delta_length(right_ski_rotation, previous_right_ski_rotation)
		))
		maximum_pelvis_correction_delta = maxf(maximum_pelvis_correction_delta, absf(pelvis_correction - previous_pelvis_correction))
		maximum_leg_compression_delta = maxf(maximum_leg_compression_delta, maxf(
			absf(left_compression - previous_left_compression),
			absf(right_compression - previous_right_compression)
		))
		maximum_contact_confidence_delta = maxf(maximum_contact_confidence_delta, maxf(
			absf(left_confidence - previous_left_confidence),
			absf(right_confidence - previous_right_confidence)
		))
		maximum_influence_delta = maxf(maximum_influence_delta, absf(correction_influence - previous_correction_influence))
	else:
		robustness_metrics_started = true
	previous_left_ski_rotation = left_ski_rotation
	previous_right_ski_rotation = right_ski_rotation
	previous_pelvis_correction = pelvis_correction
	previous_left_compression = left_compression
	previous_right_compression = right_compression
	previous_left_confidence = left_confidence
	previous_right_confidence = right_confidence
	previous_correction_influence = correction_influence
	if section == "F Transition" and skier.contact.grounded:
		minimum_awkward_confidence = minf(minimum_awkward_confidence, minf(left_confidence, right_confidence))
		minimum_awkward_correction = minf(minimum_awkward_correction, correction_influence)
		if minf(left_confidence, right_confidence) < 0.72 and correction_influence < float(debug.terrain_influence) * 0.8:
			awkward_confidence_reduced = true
		if absf(skier.edge_amount) > 0.08 and absf(float(debug.carve_target)) > 0.03:
			awkward_carve_preserved = true
	elif section == "Runout" and skier.contact.grounded and minf(left_confidence, right_confidence) > 0.78:
		confidence_recovered = true

func _euler_delta_length(current: Vector3, previous: Vector3) -> float:
	return Vector3(
		absf(wrapf(current.x - previous.x, -PI, PI)),
		absf(wrapf(current.y - previous.y, -PI, PI)),
		absf(wrapf(current.z - previous.z, -PI, PI))
	).length()

func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _run_synthetic_suspension_checks() -> void:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var sample := SkierAnimationFrame.new()
	sample.locomotion_state = 0
	sample.grounded = true
	sample.speed_ratio = 0.55
	sample.seat_distance = 0.54
	sample.left_grounded = true
	sample.right_grounded = true
	sample.left_contact_confidence = 1.0
	sample.right_contact_confidence = 1.0
	sample.left_ground_distance = 0.35
	sample.right_ground_distance = 0.71
	sample.left_normal = Vector3(0.18, 0.96, 0.2).normalized()
	sample.right_normal = Vector3(-0.2, 0.97, -0.1).normalized()
	sample.left_front_valid = true
	sample.left_rear_valid = true
	sample.right_front_valid = true
	sample.right_rear_valid = true
	sample.left_front_position = Vector3(-0.24, -0.15, -0.72)
	sample.left_rear_position = Vector3(-0.24, 0.08, 0.72)
	sample.right_front_position = Vector3(0.24, 0.06, -0.72)
	sample.right_rear_position = Vector3(0.24, -0.08, 0.72)
	sample.left_front_normal = sample.left_normal
	sample.left_rear_normal = sample.left_normal
	sample.right_front_normal = sample.right_normal
	sample.right_rear_normal = sample.right_normal
	for _index: int in 120:
		rig.apply_frame(sample, 1.0 / 120.0)
	var loaded := rig.debug_snapshot()
	if float(loaded.left_leg_compression) <= 0.35 or float(loaded.right_leg_compression) >= -0.25:
		failures.append("Independent terrain gaps did not compress the left leg and extend the right leg")
	if absf(float(loaded.terrain_pelvis_offset)) >= maxf(absf(float(loaded.left_gap)), absf(float(loaded.right_gap))):
		failures.append("Pelvis followed terrain as strongly as the skis")
	if (loaded.left_terrain_angles as Vector2).length() < 0.05 or (loaded.right_terrain_angles as Vector2).length() < 0.05:
		failures.append("Per-ski terrain normals did not orient the boots/skis")
	sample.locomotion_state = 1
	sample.grounded = false
	sample.left_grounded = false
	sample.right_grounded = false
	for _index: int in 72:
		rig.apply_frame(sample, 1.0 / 120.0)
	var airborne := rig.debug_snapshot()
	if float(airborne.terrain_influence) > 0.02 or absf(float(airborne.left_gap)) > 0.01 or absf(float(airborne.right_gap)) > 0.01:
		failures.append("Terrain suspension remained magnetized after takeoff")
	remove_child(rig)
	rig.queue_free()

func _build_course() -> void:
	var map_data := PackedFloat32Array()
	map_data.resize(MAP_WIDTH * MAP_DEPTH)
	for z_index: int in MAP_DEPTH:
		var z := _grid_z(z_index)
		for x_index: int in MAP_WIDTH:
			var x := _grid_x(x_index)
			map_data[z_index * MAP_WIDTH + x_index] = _height_at(x, z)
	var shape := HeightMapShape3D.new()
	shape.map_width = MAP_WIDTH
	shape.map_depth = MAP_DEPTH
	shape.map_data = map_data
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3(CELL_SIZE, 1.0, CELL_SIZE)
	var body := StaticBody3D.new()
	body.name = "TerrainSuspensionCourse"
	body.collision_layer = 1
	body.collision_mask = 2
	body.set_meta("ski_surface_kind", 2)
	body.add_child(collision)
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "CourseMesh"
	mesh_instance.mesh = _build_course_mesh()
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("#e8f5fb")
	snow.roughness = 0.92
	mesh_instance.material_override = snow
	add_child(mesh_instance)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b8d8ec")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.72
	world.environment = environment
	add_child(world)

func _build_course_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z_index: int in MAP_DEPTH - 1:
		for x_index: int in MAP_WIDTH - 1:
			var a := _grid_point(x_index, z_index)
			var b := _grid_point(x_index + 1, z_index)
			var c := _grid_point(x_index, z_index + 1)
			var d := _grid_point(x_index + 1, z_index + 1)
			surface.add_vertex(a)
			surface.add_vertex(c)
			surface.add_vertex(b)
			surface.add_vertex(b)
			surface.add_vertex(c)
			surface.add_vertex(d)
	surface.generate_normals()
	return surface.commit()

func _build_skier() -> void:
	skier = SkierController.new()
	skier.name = "Skier"
	add_child(skier)
	var normal := Vector3(0.0, 1.0, -0.17).normalized()
	var downhill := Vector3(0.0, -0.17, -1.0).normalized()
	var spawn := Transform3D(Basis.looking_at(downhill, normal), Vector3(0.0, _height_at(0.0, START_Z) + 1.15, START_Z))
	skier.reset_for_benchmark(spawn, downhill * 5.0)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 44.0
	add_child(camera)
	camera.global_position = skier.global_position + Vector3(3.6, 2.35, 5.6)
	camera.look_at(skier.global_position + Vector3.UP * 0.9, Vector3.UP)
	camera.current = true

func _drive_linked_turns() -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if frame_count < 360 or frame_count > 1500:
		return
	var turn_index := int((frame_count - 360) / 150)
	if turn_index % 2 == 0:
		Input.action_press("steer_left", 0.38)
	else:
		Input.action_press("steer_right", 0.38)

func _finish() -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	for section: String in ["A Smooth", "B Rollers", "C Uneven", "D Dip", "E Crest", "F Transition"]:
		if not sections_seen.has(section):
			failures.append("Course section was not traversed: " + section)
	for band: String in ["low", "medium", "high"]:
		if not bool(speed_bands_seen[band]):
			failures.append("Speed band was not exercised: " + band)
	if terrain_samples < 120:
		failures.append("Terrain influence did not remain active through grounded travel")
	if maximum_side_difference < 0.025:
		failures.append("Uneven terrain did not produce independent left/right ski response")
	if maximum_compression < 0.08:
		failures.append("Bumps did not produce visible leg compression/extension")
	if maximum_pelvis_offset >= minf(0.28, maximum_gap * 0.95):
		failures.append("Pelvis vertical response was not calmer than ski terrain travel")
	if maximum_normal_angle < 0.015:
		failures.append("Ski terrain-normal response was never exercised")
	if not air_release_seen:
		failures.append("Crest airtime did not release terrain influence")
	if not awkward_confidence_reduced:
		failures.append("Awkward transition did not attenuate low-confidence terrain correction")
	if not confidence_recovered:
		failures.append("Per-ski confidence did not recover smoothly on valid runout terrain")
	if not awkward_carve_preserved:
		failures.append("Carve pose was not preserved through the awkward transition")
	if skeleton_explosion_seen:
		failures.append("A terrain discontinuity produced a non-finite skeleton transform")
	if knee_inversion_seen:
		failures.append("A terrain discontinuity inverted a knee")
	if maximum_ski_orientation_delta > 0.09:
		failures.append("Single-frame ski orientation delta exceeded the stability limit: %.3f" % maximum_ski_orientation_delta)
	if maximum_pelvis_correction_delta > 0.05:
		failures.append("Single-frame pelvis correction delta exceeded the stability limit: %.3f" % maximum_pelvis_correction_delta)
	if maximum_leg_compression_delta > 0.2:
		failures.append("Single-frame leg compression delta exceeded the stability limit: %.3f" % maximum_leg_compression_delta)
	if maximum_contact_confidence_delta > 0.12:
		failures.append("Single-frame contact confidence delta exceeded the stability limit: %.3f" % maximum_contact_confidence_delta)
	if maximum_influence_delta > 0.12:
		failures.append("Terrain correction influence flickered too rapidly: %.3f" % maximum_influence_delta)
	if turn_sign_changes < 3:
		failures.append("Linked carve-plus-terrain turns were not exercised")
	if absf(skier.global_position.x) > 13.5:
		failures.append("Skier left the controlled terrain lane")
	print("TERRAIN_SUSPENSION_RESULT frames=%d position=%s sections=%s speed_bands=%s max_gap=%.3f side_delta=%.3f compression=%.2f pelvis=%.3f normal=%.3f turns=%d air_release=%s ski_delta=%.4f pelvis_delta=%.4f leg_delta=%.4f confidence_delta=%.4f influence_delta=%.4f awkward_confidence=%.3f awkward_correction=%.3f" % [
		frame_count,
		skier.global_position,
		sections_seen.keys(),
		speed_bands_seen,
		maximum_gap,
		maximum_side_difference,
		maximum_compression,
		maximum_pelvis_offset,
		maximum_normal_angle,
		turn_sign_changes,
		air_release_seen,
		maximum_ski_orientation_delta,
		maximum_pelvis_correction_delta,
		maximum_leg_compression_delta,
		maximum_contact_confidence_delta,
		maximum_influence_delta,
		minimum_awkward_confidence,
		minimum_awkward_correction,
	])
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("TERRAIN_SUSPENSION_PASS: confidence attenuated discontinuities, rigid skis stayed stable, the body remained bounded, air released, and linked carves remained layered")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("TERRAIN_SUSPENSION_FAIL: " + failure)
	get_tree().quit(1)

func _section_name(z: float) -> String:
	if z >= 30.0: return "A Smooth"
	if z >= 10.0: return "B Rollers"
	if z >= -10.0: return "C Uneven"
	if z >= -30.0: return "D Dip"
	if z >= -50.0: return "E Crest"
	if z >= -62.0: return "F Transition"
	return "Runout"

func _height_at(x: float, z: float) -> float:
	var height := z * 0.17
	if z < 30.0 and z >= 10.0:
		var t := (30.0 - z) / 20.0
		height += sin(t * PI * 6.0) * sin(t * PI) * 0.26
	elif z < 10.0 and z >= -10.0:
		var t := (10.0 - z) / 20.0
		height += sin(t * PI) * (sin(z * 0.72) * 0.12 + sin(x * 0.85 + z * 0.38) * 0.24)
	elif z < -10.0 and z >= -30.0:
		var t := absf(z + 20.0) / 10.0
		height -= (1.0 - t) * (1.0 - t) * 0.62
	elif z < -30.0 and z >= -50.0:
		var t := absf(z + 40.0) / 10.0
		height += (1.0 - t) * (1.0 - t) * 0.72
	elif z < -50.0 and z >= -62.0:
		var t := (-50.0 - z) / 12.0
		# Closely spaced ramp, trough, and recovery exercise front/rear disagreement
		# without introducing a vertical wall or an impossible gameplay obstacle.
		height += 0.5 * smoothstep(0.04, 0.11, t)
		height -= 0.82 * smoothstep(0.29, 0.39, t)
		height += 0.32 * smoothstep(0.67, 0.78, t)
		height += sin(t * PI) * sin(x * 0.62) * 0.07
	return height

func _grid_x(index: int) -> float:
	return (float(index) - float(MAP_WIDTH - 1) * 0.5) * CELL_SIZE

func _grid_z(index: int) -> float:
	return (float(index) - float(MAP_DEPTH - 1) * 0.5) * CELL_SIZE

func _grid_point(x_index: int, z_index: int) -> Vector3:
	var x := _grid_x(x_index)
	var z := _grid_z(z_index)
	return Vector3(x, _height_at(x, z), z)
