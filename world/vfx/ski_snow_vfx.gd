class_name SkiSnowVFX
extends Node3D

const TRACK_SHADER: Shader = preload("res://shaders/ski_tracks.gdshader")
const PARTICLE_SHADER: Shader = preload("res://shaders/snow_particle.gdshader")
const MAX_TRACK_SAMPLES := 180
const TRACK_MAX_AGE := 6.0
const TRACK_SAMPLE_INTERVAL := 0.045
const TRACK_SAMPLE_DISTANCE := 0.16
const TRACK_BREAK_DISTANCE := 3.0
const MIN_TRACK_SPEED := 1.4
const MAX_CONTINUOUS_PARTICLES := 184
const LANDING_EMITTER_WINDOW := 0.68
## Response rate for contact-spray density changes. Emitters ramp toward their
## demand each frame instead of switching on/off in one tick, so spray fades
## in and trails off rather than popping into existence.
const EMITTER_SMOOTH_RESPONSE := 12.0

var skier: SkierController
var track_mesh_instance: MeshInstance3D
var track_samples_left: Array[Dictionary] = []
var track_samples_right: Array[Dictionary] = []
var track_sample_time := 0.0
var last_left_position := Vector3.ZERO
var last_right_position := Vector3.ZERO
var last_track_valid := false
var track_rebuild_count := 0
var track_rebuild_total_usec := 0
var track_rebuild_max_usec := 0
var contact_presentation := SkiContactPresentation.new()

var carve_spray: GPUParticles3D
var skid_spray: GPUParticles3D
var landing_spray: GPUParticles3D
var speed_snow: GPUParticles3D
var bail_scrape: GPUParticles3D
var last_mode := "none"
var last_landing_severity := 0.0
var last_brake_response := 0.0
var last_bail_surface_speed := 0.0
var last_valid_contact_center := Vector3.ZERO
var last_valid_contact_normal := Vector3.UP
var last_valid_contact_allows_snow := false
var landing_window_remaining := 0.0
var _carve_anchor_smoothed := Vector3.ZERO
var _carve_anchor_initialized := false

func _ready() -> void:
	skier = get_parent() as SkierController
	_build_track_mesh()
	carve_spray = _build_particles("CarveSpray", 48, 0.38, Vector2(0.5, 2.4), Vector2(0.014, 0.042), Color(0.86, 0.93, 0.98, 0.74), 2.5)
	skid_spray = _build_particles("SkidSpray", 96, 0.56, Vector2(1.8, 6.8), Vector2(0.018, 0.062), Color(0.79, 0.89, 0.96, 0.82), 3.0)
	landing_spray = _build_particles("LandingBurst", 84, 0.38, Vector2(1.8, 6.2), Vector2(0.024, 0.085), Color(0.76, 0.88, 0.96, 0.95), 2.6)
	landing_spray.one_shot = true
	landing_spray.explosiveness = 1.0
	landing_spray.emitting = false
	speed_snow = _build_particles("SpeedSnow", 32, 0.34, Vector2(7.0, 13.0), Vector2(0.008, 0.024), Color(0.92, 0.97, 1.0, 0.46), 3.2)
	bail_scrape = _build_particles("BailScrape", 44, 0.54, Vector2(0.9, 4.6), Vector2(0.016, 0.052), Color(0.83, 0.91, 0.95, 0.72), 2.7)
	if skier != null:
		skier.landed.connect(_on_landed)
	GameSettings.settings_applied.connect(_apply_quality)
	_apply_quality()

func _exit_tree() -> void:
	# Particle curve/ramp textures allocate RenderingDevice RIDs when the GPU
	# renderer is active. Clear every material/mesh reference before the node is
	# released so visual capture shutdown cannot leave those RIDs alive until
	# RenderingServer finalization.
	release_render_resources()

func release_render_resources() -> void:
	var emitters: Array[GPUParticles3D] = [carve_spray, skid_spray, landing_spray, speed_snow, bail_scrape]
	for emitter: GPUParticles3D in emitters:
		if emitter == null:
			continue
		var process_material := emitter.process_material as ParticleProcessMaterial
		if process_material != null:
			process_material.scale_curve = null
			process_material.color_ramp = null
			process_material = null
			emitter.process_material = null
		emitter.draw_pass_1 = null
	if track_mesh_instance != null:
		track_mesh_instance.material_override = null
		track_mesh_instance.mesh = null
	carve_spray = null
	skid_spray = null
	landing_spray = null
	speed_snow = null
	bail_scrape = null
	track_mesh_instance = null

func update_from_existing_contact(delta: float) -> void:
	if skier == null:
		return
	landing_window_remaining = maxf(landing_window_remaining - delta, 0.0)
	# Single-burst contract: the landing one-shot fires exactly once per
	# landed event (see _on_landed). The window extends landing MODE
	# bookkeeping for telemetry and evidence only; re-triggering the emitter
	# inside it reads as repeated bursts for a single landing.
	if landing_window_remaining <= 0.0:
		if landing_spray != null and landing_spray.emitting:
			landing_spray.emitting = false
	# SkiContactPresentation captures skier.contact.left_hit_position and
	# skier.contact.right_hit_position once for every presentation adapter.
	contact_presentation.capture(skier.contact)
	if contact_presentation.left_valid or contact_presentation.right_valid:
		last_valid_contact_center = _presentation_center()
		last_valid_contact_normal = _presentation_normal()
		last_valid_contact_allows_snow = contact_presentation.allows_snow_effects()
	_age_track_samples(delta)
	var speed := skier.velocity.length()
	var grounded := skier.state == SkierController.State.GROUND and skier.contact.grounded
	track_sample_time += delta
	if grounded and contact_presentation.allows_snow_effects() and speed >= MIN_TRACK_SPEED:
		_update_tracks(speed)
		_update_continuous_spray(speed, delta)
		_set_emitter_density(bail_scrape, 0.0, delta)
	elif skier.state == SkierController.State.BAIL and skier.contact.grounded and contact_presentation.allows_snow_effects() and speed >= 0.9:
		last_track_valid = false
		_set_emitter_density(carve_spray, 0.0, delta)
		_set_emitter_density(skid_spray, 0.0, delta)
		_update_bail_scrape(speed, delta)
	else:
		last_track_valid = false
		_set_emitter_density(carve_spray, 0.0, delta)
		_set_emitter_density(skid_spray, 0.0, delta)
		_set_emitter_density(bail_scrape, 0.0, delta)
		last_mode = "none"
	_update_speed_snow(speed)

## Ramps an emitter's density toward its demand and gates visibility on the
## smoothed value, so contact spray never starts or stops in a single frame.
static func smooth_emitter_ratio(current: float, target: float, delta: float, response: float = EMITTER_SMOOTH_RESPONSE) -> float:
	return current + (clampf(target, 0.0, 1.0) - current) * (1.0 - exp(-maxf(response, 0.01) * maxf(delta, 0.0)))

func _set_emitter_density(emitter: GPUParticles3D, target: float, delta: float) -> void:
	if emitter == null:
		return
	emitter.amount_ratio = smooth_emitter_ratio(emitter.amount_ratio, target, delta)
	emitter.emitting = emitter.amount_ratio > 0.04

func clear_transient_effects() -> void:
	last_track_valid = false
	_carve_anchor_initialized = false
	for emitter: GPUParticles3D in [carve_spray, skid_spray, speed_snow, bail_scrape]:
		if emitter == null:
			continue
		emitter.amount_ratio = 0.0
		emitter.emitting = false
	# Landing feedback is a one-shot event. The skier emits `landed` before
	# entering control recovery, so clearing the continuous effects here must
	# not erase a burst that was just restarted by _on_landed().

func debug_snapshot() -> Dictionary:
	return {
		"left_track_samples": track_samples_left.size(),
		"right_track_samples": track_samples_right.size(),
		"track_cap": MAX_TRACK_SAMPLES,
		"track_rebuild_count": track_rebuild_count,
		"track_rebuild_average_usec": float(track_rebuild_total_usec) / maxf(float(track_rebuild_count), 1.0),
		"track_rebuild_max_usec": track_rebuild_max_usec,
		"continuous_particle_cap": MAX_CONTINUOUS_PARTICLES,
		"mode": "landing" if landing_window_remaining > 0.0 else last_mode,
		"landing_severity": last_landing_severity,
		"landing_spray_active": landing_spray.emitting if landing_spray != null else false,
		"landing_amount": landing_spray.amount if landing_spray != null else 0,
		"landing_amount_ratio": landing_spray.amount_ratio if landing_spray != null else 0.0,
		"landing_window_remaining": landing_window_remaining,
		"brake_response": last_brake_response,
		"bail_surface_speed": last_bail_surface_speed,
		"bail_scrape_active": bail_scrape.emitting if bail_scrape != null else false,
		"surface_class": contact_presentation.surface_class,
		"snow_contact": contact_presentation.allows_snow_effects() or last_valid_contact_allows_snow,
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

func _build_particles(label: String, amount: int, lifetime: float, velocity_range: Vector2, scale_range: Vector2, color: Color, shape_aspect: float = 1.65) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = label
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.5
	particles.explosiveness = 0.12
	particles.visibility_aabb = AABB(Vector3(-9.0, -3.0, -9.0), Vector3(18.0, 11.0, 18.0))
	particles.visibility_range_begin = 0.18
	particles.visibility_range_end = 72.0
	particles.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	particles.local_coords = false
	particles.top_level = true
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.42, 0.55)
	process_material.spread = 42.0
	process_material.initial_velocity_min = velocity_range.x
	process_material.initial_velocity_max = velocity_range.y
	process_material.gravity = Vector3(0.0, -8.0, 0.0)
	process_material.damping_min = 0.35
	process_material.damping_max = 1.15
	process_material.scale_min = scale_range.x
	process_material.scale_max = scale_range.y
	process_material.color = color
	# Keep the particle resource graph texture-free. The snow particle shader
	# already provides distance/height fading and a shaped fleck edge; CurveTexture
	# and GradientTexture1D resources add GPU RIDs that can outlive a short visual
	# capture and trigger renderer shutdown leak warnings.
	particles.process_material = process_material
	# A camera-facing quad keeps the spray light and directional. The old
	# low-resolution sphere read as a string of obvious white beads whenever a
	# carve or skid emitter crossed the camera.
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(1.0, 1.0)
	var particle_material := ShaderMaterial.new()
	particle_material.shader = PARTICLE_SHADER
	particle_material.set_shader_parameter("snow_tint", color)
	particle_material.set_shader_parameter("height_limit", 2.25)
	particle_material.set_shader_parameter("height_fade_range", 0.65)
	particle_material.set_shader_parameter("emitter_base_height", 0.0)
	particle_material.set_shader_parameter("shape_aspect", shape_aspect)
	particle_mesh.material = particle_material
	particles.draw_pass_1 = particle_mesh
	add_child(particles)
	return particles

func _apply_quality() -> void:
	var premium := int(GameSettings.active.get("snow_quality", 1)) == 1
	carve_spray.amount = 38 if premium else 22
	skid_spray.amount = 78 if premium else 44
	landing_spray.amount = 84 if premium else 48
	speed_snow.amount = 24 if premium else 14
	bail_scrape.amount = 44 if premium else 24

func _update_tracks(speed: float) -> void:
	if track_sample_time < TRACK_SAMPLE_INTERVAL:
		return
	var left_valid := contact_presentation.left_valid
	var right_valid := contact_presentation.right_valid
	if not left_valid and not right_valid:
		last_track_valid = false
		return
	var left_position := contact_presentation.left_position
	var right_position := contact_presentation.right_position
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
	var width := lerpf(0.045, 0.18, skid)
	width += clampf(speed / maxf(skier.profile.maximum_speed, 1.0), 0.0, 1.0) * 0.015
	if left_valid:
		var connected_left := last_track_valid and left_position.distance_to(last_left_position) <= TRACK_BREAK_DISTANCE
		_append_track_sample(track_samples_left, left_position, contact_presentation.left_normal, width, skid, carve_strength, connected_left)
		last_left_position = left_position
	if right_valid:
		var connected_right := last_track_valid and right_position.distance_to(last_right_position) <= TRACK_BREAK_DISTANCE
		_append_track_sample(track_samples_right, right_position, contact_presentation.right_normal, width, skid, carve_strength, connected_right)
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
		"disturbance": clampf(maxf(skid, carve * 0.46), 0.0, 1.0),
		"age": 0.0,
		"connected": connected,
	})
	if samples.size() > MAX_TRACK_SAMPLES:
		samples.pop_front()
		if not samples.is_empty():
			samples[0].connected = false

func _rebuild_track_mesh() -> void:
	# Skip no-op uploads: with fewer than two samples in both ribbons there is
	# no quad to draw, and committing on every such call only churns
	# SurfaceTool/ArrayMesh allocations during ordinary movement.
	if track_samples_left.size() < 2 and track_samples_right.size() < 2:
		return
	var start_usec := Time.get_ticks_usec()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_track_ribbon(surface, track_samples_left)
	_add_track_ribbon(surface, track_samples_right)
	var rebuilt := surface.commit()
	# An empty commit (all ribbons disconnected or degenerate) must not wipe
	# the last good ribbon: stale-but-visible beats a one-frame wipe.
	if rebuilt != null and rebuilt.get_surface_count() > 0:
		track_mesh_instance.mesh = rebuilt
	elif track_mesh_instance.mesh == null:
		track_mesh_instance.mesh = rebuilt
	else:
		return
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	track_rebuild_count += 1
	track_rebuild_total_usec += elapsed_usec
	track_rebuild_max_usec = maxi(track_rebuild_max_usec, elapsed_usec)

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
		# UV.x spans the groove; normals and age remain attached to each endpoint.
		for vertex: Array in [
			[a_left, normal_a, previous, age_alpha_a, 0.0],
			[b_left, normal_b, current, age_alpha_b, 0.0],
			[b_right, normal_b, current, age_alpha_b, 1.0],
			[a_left, normal_a, previous, age_alpha_a, 0.0],
			[b_right, normal_b, current, age_alpha_b, 1.0],
			[a_right, normal_a, previous, age_alpha_a, 1.0],
		]:
			_add_track_vertex(surface, vertex[0], vertex[1], float(vertex[2].disturbance), float(vertex[2].carve), vertex[3], vertex[4])

func _add_track_vertex(surface: SurfaceTool, position: Vector3, normal: Vector3, disturbance: float, carve: float, alpha: float, across: float) -> void:
	surface.set_normal(normal)
	surface.set_uv(Vector2(across, 0.0))
	surface.set_color(Color(disturbance, carve, 0.0, alpha))
	surface.add_vertex(position)

func _set_particle_emitter_height(particles: GPUParticles3D, height: float) -> void:
	if particles == null or particles.draw_pass_1 == null:
		return
	var mesh: Mesh = particles.draw_pass_1
	var mat: Material = mesh.material if mesh is Mesh else null
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("emitter_base_height", height)

func _update_continuous_spray(speed: float, delta: float) -> void:
	# Raw contact center: every emitter adds its own single surface lift
	# below, so the shared helper must not pre-lift (that stacked +0.08 twice
	# on center-routed sprays while side-routed sprays sat exact).
	var contact_position := _presentation_center()
	var normal := _presentation_normal()
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
	var left_contact := contact_presentation.left_position if contact_presentation.left_valid else contact_position
	var right_contact := contact_presentation.right_position if contact_presentation.right_valid else contact_position
	# VFX-01: carve spray belongs to the loaded outside ski, never a fixed
	# side. Turn sign is the kinematic heading angle (positive = left turn =
	# loaded right ski); near-straight running stays centered, and an invalid
	# dominant side falls back to the contact center.
	var turn_side := 0.0
	if absf(skier.heading_travel_angle_degrees) > 3.0:
		turn_side = signf(skier.heading_travel_angle_degrees)
	var carve_anchor := contact_position
	if turn_side > 0.0 and contact_presentation.right_valid:
		carve_anchor = right_contact
	elif turn_side < 0.0 and contact_presentation.left_valid:
		carve_anchor = left_contact
	if not _carve_anchor_initialized:
		_carve_anchor_initialized = true
		_carve_anchor_smoothed = carve_anchor
	_carve_anchor_smoothed = _carve_anchor_smoothed.lerp(carve_anchor, 1.0 - exp(-EMITTER_SMOOTH_RESPONSE * delta))
	# Skid spray washes off both sliding skis, so it rides the contact center
	# with slip-signed ejection instead of a fixed side.
	carve_spray.global_position = _carve_anchor_smoothed + normal * 0.08 - travel * 0.45
	skid_spray.global_position = contact_position + normal * 0.08 - travel * 0.3
	_set_particle_emitter_height(carve_spray, carve_spray.global_position.y)
	_set_particle_emitter_height(skid_spray, skid_spray.global_position.y)
	var carve_material := carve_spray.process_material as ParticleProcessMaterial
	carve_material.direction = normal * 0.42 - travel * 0.82 + right * turn_side * 0.55
	carve_material.spread = 24.0
	var lateral_sign := signf(skier.lateral_slip)
	if is_zero_approx(lateral_sign):
		lateral_sign = signf(skier.edge_amount)
	var skid_material := skid_spray.process_material as ParticleProcessMaterial
	skid_material.direction = (normal * 0.44 + right * lateral_sign * 0.92 - travel * 0.18).normalized()
	skid_material.spread = lerpf(34.0, 62.0, maxf(skid, brake))
	skid_material.initial_velocity_min = lerpf(1.8, 2.8, brake)
	skid_material.initial_velocity_max = lerpf(6.8, 8.2, brake)
	var carve_target := clampf(carve * speed_ratio * (1.0 - skid * 0.78), 0.0, 0.52)
	var skid_demand := maxf((skid - 0.16) / 0.84, brake * 0.82)
	var skid_target := clampf(skid_demand * speed_ratio, 0.0, 1.0)
	_set_emitter_density(carve_spray, carve_target, delta)
	_set_emitter_density(skid_spray, skid_target, delta)
	last_mode = "brake" if skid_spray.emitting and brake > 0.2 else ("skid" if skid_spray.emitting else ("carve" if carve_spray.emitting else "track"))

func _update_bail_scrape(speed: float, delta: float) -> void:
	var normal := _presentation_normal()
	if normal.length_squared() < 0.001:
		normal = Vector3.UP
	var surface_velocity := skier.velocity.slide(normal)
	last_bail_surface_speed = surface_velocity.length()
	if last_bail_surface_speed < 0.9:
		_set_emitter_density(bail_scrape, 0.0, delta)
		return
	var travel := surface_velocity.normalized()
	bail_scrape.global_position = _presentation_center() + normal * 0.12 - travel * 0.24
	_set_particle_emitter_height(bail_scrape, bail_scrape.global_position.y)
	var process_material := bail_scrape.process_material as ParticleProcessMaterial
	process_material.direction = (normal * 0.52 - travel * 0.86).normalized()
	process_material.spread = 54.0
	process_material.initial_velocity_min = lerpf(0.9, 2.0, clampf(last_bail_surface_speed / 14.0, 0.0, 1.0))
	process_material.initial_velocity_max = lerpf(3.2, 6.5, clampf(last_bail_surface_speed / 14.0, 0.0, 1.0))
	_set_emitter_density(bail_scrape, clampf((last_bail_surface_speed - 0.9) / 9.0, 0.12, 0.78), delta)
	last_mode = "bail_scrape"

func _update_speed_snow(speed: float) -> void:
	var speed_ratio := clampf((speed - 18.0) / 15.0, 0.0, 1.0)
	var surface_allows_effects := skier.state != SkierController.State.GROUND or contact_presentation.allows_snow_effects()
	speed_snow.emitting = speed_ratio > 0.02 and skier.state != SkierController.State.BAIL and surface_allows_effects
	speed_snow.amount_ratio = speed_ratio * 0.48
	speed_snow.global_position = skier.global_position + Vector3.UP * 1.0
	_set_particle_emitter_height(speed_snow, speed_snow.global_position.y)
	var process_material := speed_snow.process_material as ParticleProcessMaterial
	var direction := -skier.velocity.normalized() if speed > 0.1 else Vector3.BACK
	process_material.direction = direction
	process_material.spread = 16.0

func _on_landed(result: Dictionary) -> void:
	var severity := clampf(float(result.get("impact_severity", 0.0)), 0.0, 1.0)
	last_landing_severity = severity
	# Clean, low-energy landings still need a small contact cue. Suppressing
	# every burst below the old threshold made a successful stomp look like a
	# frame of hovering with no snow response.
	if severity < 0.03:
		return
	contact_presentation.capture(skier.contact)
	var current_contact_allows_snow := contact_presentation.allows_snow_effects()
	var authoritative_landing_contact := (
		skier.contact.grounded
		and skier.contact.surface_class == SkiContactSolver.SurfaceClass.SNOW
		and skier.contact.average_hit_position.length_squared() > 0.001
	)
	if not current_contact_allows_snow and not authoritative_landing_contact and not last_valid_contact_allows_snow:
		return
	# The landing signal can arrive before the per-ski confidence values finish
	# their transition back to grounded. Prefer the solver's current averaged hit
	# point in that narrow window so the burst follows the actual landing rather
	# than the last contact point from takeoff.
	var use_authoritative_contact := authoritative_landing_contact and not current_contact_allows_snow
	var normal := _presentation_normal() if current_contact_allows_snow else (skier.contact.average_normal if use_authoritative_contact else last_valid_contact_normal)
	var center := _presentation_center() if current_contact_allows_snow else (skier.contact.average_hit_position if use_authoritative_contact else last_valid_contact_center)
	if normal.length_squared() < 0.001:
		normal = Vector3.UP
	landing_spray.global_position = center + normal * 0.1
	_set_particle_emitter_height(landing_spray, landing_spray.global_position.y)
	var process_material := landing_spray.process_material as ParticleProcessMaterial
	var lateral := float(result.get("lateral_velocity", 0.0))
	var travel := skier.velocity.slide(normal).normalized()
	var right := travel.cross(normal).normalized() if travel.length_squared() > 0.01 else skier.global_basis.x
	process_material.direction = (normal * 0.9 + right * signf(lateral) * minf(absf(lateral) / 8.0, 0.65) - travel * 0.18).normalized()
	process_material.spread = lerpf(44.0, 62.0, severity)
	process_material.initial_velocity_min = lerpf(1.25, 3.2, severity)
	process_material.initial_velocity_max = lerpf(2.8, 6.2, severity)
	landing_spray.amount_ratio = lerpf(0.34, 0.88, severity)
	landing_window_remaining = LANDING_EMITTER_WINDOW
	last_mode = "landing"
	landing_spray.emitting = true
	landing_spray.restart()

func _age_track_samples(delta: float) -> void:
	_age_track_sample_array(track_samples_left, delta)
	_age_track_sample_array(track_samples_right, delta)

func _age_track_sample_array(samples: Array[Dictionary], delta: float) -> void:
	var changed := false
	for index: int in range(samples.size() - 1, -1, -1):
		var sample: Dictionary = samples[index]
		sample["age"] = float(sample.get("age", 0.0)) + delta
		if float(sample.get("age", 0.0)) > TRACK_MAX_AGE:
			samples.remove_at(index)
			changed = true
	if changed:
		_rebuild_track_mesh()

func _presentation_center() -> Vector3:
	if contact_presentation.left_valid and contact_presentation.right_valid:
		return (contact_presentation.left_position + contact_presentation.right_position) * 0.5
	if contact_presentation.left_valid:
		return contact_presentation.left_position
	return contact_presentation.right_position

func _presentation_normal() -> Vector3:
	if contact_presentation.left_valid and contact_presentation.right_valid:
		return (contact_presentation.left_normal + contact_presentation.right_normal).normalized()
	if contact_presentation.left_valid:
		return contact_presentation.left_normal
	return contact_presentation.right_normal
