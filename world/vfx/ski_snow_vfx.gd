class_name SkiSnowVFX
extends Node3D

const TRACK_SHADER: Shader = preload("res://shaders/ski_tracks.gdshader")
const MAX_TRACK_SAMPLES := 180
const TRACK_SAMPLE_INTERVAL := 0.045
const TRACK_SAMPLE_DISTANCE := 0.16
const TRACK_BREAK_DISTANCE := 3.0
const MIN_TRACK_SPEED := 1.4
const MAX_CONTINUOUS_PARTICLES := 184

var skier: SkierController
var track_mesh_instance: MeshInstance3D
var track_samples_left: Array[Dictionary] = []
var track_samples_right: Array[Dictionary] = []
var track_sample_time := 0.0
var last_left_position := Vector3.ZERO
var last_right_position := Vector3.ZERO
var last_track_valid := false

var carve_spray: GPUParticles3D
var skid_spray: GPUParticles3D
var landing_spray: GPUParticles3D
var speed_snow: GPUParticles3D
var bail_scrape: GPUParticles3D
var last_mode := "none"
var last_landing_severity := 0.0
var last_brake_response := 0.0
var last_bail_surface_speed := 0.0

func _ready() -> void:
	skier = get_parent() as SkierController
	_build_track_mesh()
	carve_spray = _build_particles("CarveSpray", 48, 0.48, Vector2(0.5, 2.4), Vector2(0.022, 0.065), Color(0.86, 0.93, 0.98, 0.74))
	skid_spray = _build_particles("SkidSpray", 96, 0.72, Vector2(1.8, 6.8), Vector2(0.028, 0.11), Color(0.79, 0.89, 0.96, 0.82))
	landing_spray = _build_particles("LandingBurst", 64, 0.62, Vector2(2.2, 7.8), Vector2(0.032, 0.13), Color(0.9, 0.96, 1.0, 0.9))
	landing_spray.one_shot = true
	landing_spray.explosiveness = 1.0
	landing_spray.emitting = false
	speed_snow = _build_particles("SpeedSnow", 32, 0.42, Vector2(7.0, 13.0), Vector2(0.012, 0.032), Color(0.92, 0.97, 1.0, 0.46))
	bail_scrape = _build_particles("BailScrape", 44, 0.68, Vector2(0.9, 4.6), Vector2(0.024, 0.085), Color(0.83, 0.91, 0.95, 0.72))
	if skier != null:
		skier.landed.connect(_on_landed)
	GameSettings.settings_applied.connect(_apply_quality)
	_apply_quality()

func update_from_existing_contact(delta: float) -> void:
	if skier == null:
		return
	var speed := skier.velocity.length()
	var grounded := skier.state == SkierController.State.GROUND and skier.contact.grounded
	track_sample_time += delta
	if grounded and speed >= MIN_TRACK_SPEED:
		_update_tracks(speed)
		_update_continuous_spray(speed)
		bail_scrape.emitting = false
	elif skier.state == SkierController.State.BAIL and skier.contact.grounded and speed >= 0.9:
		last_track_valid = false
		carve_spray.emitting = false
		skid_spray.emitting = false
		_update_bail_scrape(speed)
	else:
		last_track_valid = false
		carve_spray.emitting = false
		skid_spray.emitting = false
		bail_scrape.emitting = false
		last_mode = "none"
	_update_speed_snow(speed)

func clear_transient_effects() -> void:
	last_track_valid = false
	carve_spray.emitting = false
	skid_spray.emitting = false
	speed_snow.emitting = false
	bail_scrape.emitting = false
	landing_spray.emitting = false

func debug_snapshot() -> Dictionary:
	return {
		"left_track_samples": track_samples_left.size(),
		"right_track_samples": track_samples_right.size(),
		"track_cap": MAX_TRACK_SAMPLES,
		"continuous_particle_cap": MAX_CONTINUOUS_PARTICLES,
		"mode": last_mode,
		"landing_severity": last_landing_severity,
		"brake_response": last_brake_response,
		"bail_surface_speed": last_bail_surface_speed,
		"bail_scrape_active": bail_scrape.emitting if bail_scrape != null else false,
		"uses_existing_contact": skier != null,
	}

func _build_track_mesh() -> void:
	track_mesh_instance = MeshInstance3D.new()
	track_mesh_instance.name = "PersistentSkiTracks"
	track_mesh_instance.top_level = true
	track_mesh_instance.position = Vector3.ZERO
	track_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track_mesh_instance.visibility_range_end = 120.0
	track_mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var material := ShaderMaterial.new()
	material.shader = TRACK_SHADER
	track_mesh_instance.material_override = material
	add_child(track_mesh_instance)

func _build_particles(label: String, amount: int, lifetime: float, velocity_range: Vector2, scale_range: Vector2, color: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.38
	particles.explosiveness = 0.08
	particles.visibility_aabb = AABB(Vector3(-9.0, -3.0, -9.0), Vector3(18.0, 11.0, 18.0))
	particles.local_coords = false
	particles.top_level = true
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.72, 0.55)
	process_material.spread = 42.0
	process_material.initial_velocity_min = velocity_range.x
	process_material.initial_velocity_max = velocity_range.y
	process_material.gravity = Vector3(0.0, -5.8, 0.0)
	process_material.damping_min = 0.35
	process_material.damping_max = 1.15
	process_material.scale_min = scale_range.x
	process_material.scale_max = scale_range.y
	process_material.color = color
	particles.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.orientation = PlaneMesh.FACE_Z
	var particle_material := StandardMaterial3D.new()
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_material.albedo_color = color
	quad.material = particle_material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles

func _apply_quality() -> void:
	var premium := int(GameSettings.active.get("snow_quality", 1)) == 1
	carve_spray.amount = 38 if premium else 22
	skid_spray.amount = 78 if premium else 44
	landing_spray.amount = 64 if premium else 38
	speed_snow.amount = 24 if premium else 14
	bail_scrape.amount = 44 if premium else 24

func _update_tracks(speed: float) -> void:
	if track_sample_time < TRACK_SAMPLE_INTERVAL:
		return
	var left_valid := skier.contact.left_grounded and skier.contact.left_contact_confidence > 0.2
	var right_valid := skier.contact.right_grounded and skier.contact.right_contact_confidence > 0.2
	if not left_valid and not right_valid:
		last_track_valid = false
		return
	var left_position := skier.contact.left_hit_position
	var right_position := skier.contact.right_hit_position
	var moved_enough := not last_track_valid
	if left_valid and last_track_valid:
		moved_enough = moved_enough or left_position.distance_to(last_left_position) >= TRACK_SAMPLE_DISTANCE
	if right_valid and last_track_valid:
		moved_enough = moved_enough or right_position.distance_to(last_right_position) >= TRACK_SAMPLE_DISTANCE
	if not moved_enough:
		return
	track_sample_time = 0.0
	var skid := clampf(skier.skid_amount, 0.0, 1.0)
	var carve_strength := clampf(skier.current_carve_ratio * absf(skier.edge_amount), 0.0, 1.0)
	var width := lerpf(0.055, 0.23, skid)
	width += clampf(speed / maxf(skier.profile.maximum_speed, 1.0), 0.0, 1.0) * 0.015
	if left_valid:
		var connected_left := last_track_valid and left_position.distance_to(last_left_position) <= TRACK_BREAK_DISTANCE
		_append_track_sample(track_samples_left, left_position, skier.contact.left_normal, width, skid, carve_strength, connected_left)
		last_left_position = left_position
	if right_valid:
		var connected_right := last_track_valid and right_position.distance_to(last_right_position) <= TRACK_BREAK_DISTANCE
		_append_track_sample(track_samples_right, right_position, skier.contact.right_normal, width, skid, carve_strength, connected_right)
		last_right_position = right_position
	last_track_valid = left_valid and right_valid
	_rebuild_track_mesh()

func _append_track_sample(samples: Array[Dictionary], position: Vector3, normal: Vector3, width: float, skid: float, carve: float, connected: bool) -> void:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	samples.append({
		"position": position + safe_normal * 0.018,
		"normal": safe_normal,
		"width": width,
		"skid": skid,
		"carve": carve,
		"connected": connected,
	})
	if samples.size() > MAX_TRACK_SAMPLES:
		samples.pop_front()
		if not samples.is_empty():
			samples[0].connected = false

func _rebuild_track_mesh() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_track_ribbon(surface, track_samples_left)
	_add_track_ribbon(surface, track_samples_right)
	track_mesh_instance.mesh = surface.commit()

func _add_track_ribbon(surface: SurfaceTool, samples: Array[Dictionary]) -> void:
	if samples.size() < 2:
		return
	for index: int in range(1, samples.size()):
		var current: Dictionary = samples[index]
		if not bool(current.connected):
			continue
		var previous: Dictionary = samples[index - 1]
		var a: Vector3 = previous.position
		var b: Vector3 = current.position
		var normal_a: Vector3 = previous.normal
		var normal_b: Vector3 = current.normal
		var tangent := b - a
		if tangent.length_squared() < 0.0001:
			continue
		tangent = tangent.normalized()
		var across_a := normal_a.cross(tangent).normalized()
		var across_b := normal_b.cross(tangent).normalized()
		if across_a.length_squared() < 0.001 or across_b.length_squared() < 0.001:
			continue
		var age_alpha_a := lerpf(0.2, 0.78, float(index - 1) / maxf(float(samples.size() - 1), 1.0))
		var age_alpha_b := lerpf(0.2, 0.78, float(index) / maxf(float(samples.size() - 1), 1.0))
		var half_width_a := float(previous.width) * 0.5
		var half_width_b := float(current.width) * 0.5
		var a_left := a - across_a * half_width_a
		var a_right := a + across_a * half_width_a
		var b_left := b - across_b * half_width_b
		var b_right := b + across_b * half_width_b
		_add_track_triangle(surface, a_left, b_left, b_right, normal_a, normal_b, float(previous.skid), float(current.skid), age_alpha_a, age_alpha_b)
		_add_track_triangle(surface, a_left, b_right, a_right, normal_a, normal_b, float(previous.skid), float(current.skid), age_alpha_a, age_alpha_b)

func _add_track_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal_a: Vector3, normal_b: Vector3, skid_a: float, skid_b: float, alpha_a: float, alpha_b: float) -> void:
	_add_track_vertex(surface, a, normal_a, skid_a, alpha_a)
	_add_track_vertex(surface, b, normal_b, skid_b, alpha_b)
	_add_track_vertex(surface, c, normal_b, skid_b, alpha_b)

func _add_track_vertex(surface: SurfaceTool, position: Vector3, normal: Vector3, skid: float, alpha: float) -> void:
	surface.set_normal(normal)
	surface.set_color(Color(skid, 0.0, 0.0, alpha))
	surface.add_vertex(position)

func _update_continuous_spray(speed: float) -> void:
	var contact_position := skier.contact.average_hit_position + skier.contact.average_normal * 0.08
	var normal := skier.contact.average_normal.normalized()
	var travel := skier.velocity.slide(normal)
	if travel.length_squared() < 0.01:
		travel = -skier.global_basis.z
	travel = travel.normalized()
	var right := travel.cross(normal).normalized()
	var skid := clampf(skier.skid_amount, 0.0, 1.0)
	var carve := clampf(skier.current_carve_ratio * absf(skier.edge_amount), 0.0, 1.0)
	var brake := clampf(skier.brake_amount, 0.0, 1.0)
	last_brake_response = brake
	var speed_ratio := clampf((speed - 3.0) / 20.0, 0.0, 1.0)
	carve_spray.global_position = contact_position - travel * 0.45
	skid_spray.global_position = contact_position - travel * 0.3
	var carve_material := carve_spray.process_material as ParticleProcessMaterial
	carve_material.direction = normal * 0.58 - travel * 0.82
	carve_material.spread = 24.0
	var lateral_sign := signf(skier.lateral_slip)
	if is_zero_approx(lateral_sign):
		lateral_sign = signf(skier.edge_amount)
	var skid_material := skid_spray.process_material as ParticleProcessMaterial
	skid_material.direction = (normal * 0.62 + right * lateral_sign * 0.92 - travel * 0.18).normalized()
	skid_material.spread = lerpf(34.0, 62.0, maxf(skid, brake))
	skid_material.initial_velocity_min = lerpf(1.8, 2.8, brake)
	skid_material.initial_velocity_max = lerpf(6.8, 8.2, brake)
	carve_spray.amount_ratio = clampf(carve * speed_ratio * (1.0 - skid * 0.78), 0.0, 0.52)
	var skid_demand := maxf((skid - 0.16) / 0.84, brake * 0.82)
	skid_spray.amount_ratio = clampf(skid_demand * speed_ratio, 0.0, 1.0)
	carve_spray.emitting = carve_spray.amount_ratio > 0.04
	skid_spray.emitting = skid_spray.amount_ratio > 0.04
	last_mode = "brake" if skid_spray.emitting and brake > 0.2 else ("skid" if skid_spray.emitting else ("carve" if carve_spray.emitting else "track"))

func _update_bail_scrape(speed: float) -> void:
	var normal := skier.contact.average_normal.normalized()
	if normal.length_squared() < 0.001:
		normal = Vector3.UP
	var surface_velocity := skier.velocity.slide(normal)
	last_bail_surface_speed = surface_velocity.length()
	if last_bail_surface_speed < 0.9:
		bail_scrape.emitting = false
		return
	var travel := surface_velocity.normalized()
	bail_scrape.global_position = skier.contact.average_hit_position + normal * 0.12 - travel * 0.24
	var process_material := bail_scrape.process_material as ParticleProcessMaterial
	process_material.direction = (normal * 0.52 - travel * 0.86).normalized()
	process_material.spread = 54.0
	process_material.initial_velocity_min = lerpf(0.9, 2.0, clampf(last_bail_surface_speed / 14.0, 0.0, 1.0))
	process_material.initial_velocity_max = lerpf(3.2, 6.5, clampf(last_bail_surface_speed / 14.0, 0.0, 1.0))
	bail_scrape.amount_ratio = clampf((last_bail_surface_speed - 0.9) / 9.0, 0.12, 0.78)
	bail_scrape.emitting = true
	last_mode = "bail_scrape"

func _update_speed_snow(speed: float) -> void:
	var speed_ratio := clampf((speed - 18.0) / 15.0, 0.0, 1.0)
	speed_snow.emitting = speed_ratio > 0.02 and skier.state != SkierController.State.BAIL
	speed_snow.amount_ratio = speed_ratio * 0.48
	speed_snow.global_position = skier.global_position + Vector3.UP * 1.0
	var process_material := speed_snow.process_material as ParticleProcessMaterial
	var direction := -skier.velocity.normalized() if speed > 0.1 else Vector3.BACK
	process_material.direction = direction
	process_material.spread = 16.0

func _on_landed(result: Dictionary) -> void:
	var severity := clampf(float(result.get("impact_severity", 0.0)), 0.0, 1.0)
	last_landing_severity = severity
	if severity < 0.08:
		return
	var normal := skier.contact.average_normal.normalized()
	landing_spray.global_position = skier.contact.average_hit_position + normal * 0.1
	var process_material := landing_spray.process_material as ParticleProcessMaterial
	var lateral := float(result.get("lateral_velocity", 0.0))
	var travel := skier.velocity.slide(normal).normalized()
	var right := travel.cross(normal).normalized() if travel.length_squared() > 0.01 else skier.global_basis.x
	process_material.direction = (normal * 0.9 + right * signf(lateral) * minf(absf(lateral) / 8.0, 0.65) - travel * 0.18).normalized()
	process_material.spread = lerpf(48.0, 68.0, severity)
	process_material.initial_velocity_min = lerpf(1.8, 4.2, severity)
	process_material.initial_velocity_max = lerpf(4.0, 9.2, severity)
	landing_spray.amount_ratio = lerpf(0.28, 1.0, severity)
	landing_spray.emitting = true
	landing_spray.restart()
