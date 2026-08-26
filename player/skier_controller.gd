class_name SkierController
extends CharacterBody3D

signal state_changed(state_name: String)
signal telemetry_updated(data: Dictionary)
signal landed(result: Dictionary)
signal crashed

enum State { GROUND, AIR, GRIND, BAIL }

@export var profile: SkiPhysicsProfile = preload("res://resources/physics/default_ski_profile.tres")
@export var flick_profile: FlickTrickProfile = preload("res://resources/physics/default_flick_trick_profile.tres")

var state := State.AIR
var contact := SkiContactSolver.new()
var angular_velocity := Vector3.ZERO
var edge_amount := 0.0
var lateral_slip := 0.0
var carve_force := 0.0
var coyote_remaining := 0.0
var jump_charge := 0.0
var tuck_amount := 0.0
var braking := false
var air_time := 0.0
var rail_balance_input := 0.0
var active_rail: GrindRail3D
var rail_offset := 0.0
var rail_direction := 1.0
var rail_speed := 0.0
var bail_time := 0.0
var debug_enabled := false
var trick: TrickController
var spray: GPUParticles3D
var visual_root: Node3D
var animation_controller: SkierAnimationController
var animation_frame := SkierAnimationFrame.new()
var debug_mesh: ImmediateMesh
var flick: FlickTrickInterpreter
var trick_sample := TrickInputSample.new()
var trick_command: TrickCommand
var active_trick_kind := TrickCommand.Kind.NONE
var trick_phase := TrickCommand.PresentationPhase.NEUTRAL
var gesture_strength := 0.0
var grab_amount := 0.0
var grab_tweak := Vector2.ZERO
var grab_release_time := 0.0
var rail_pose := 0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 5
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.42
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_build_body()
	_build_spray()
	_build_debug_draw()
	trick = TrickController.new()
	add_child(trick)
	flick = FlickTrickInterpreter.new(flick_profile)
	trick_command = TrickCommand.new()
	SessionManager.respawn_requested.connect(respawn_at)
	state_changed.emit("Air")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		debug_enabled = not debug_enabled
	if event.is_action_pressed("respawn"):
		SessionManager.request_respawn()
	if event.is_action_pressed("set_marker") and state == State.GROUND and contact.grounded:
		var safe_transform := global_transform
		safe_transform.origin += contact.average_normal * 0.5
		SessionManager.set_marker(safe_transform)

func _physics_process(delta: float) -> void:
	contact.sample(self)
	_sample_trick_input(delta)
	match state:
		State.GROUND: _update_ground(delta)
		State.AIR: _update_air(delta)
		State.GRIND: _update_grind(delta)
		State.BAIL: _update_bail(delta)
	if state != State.GRIND:
		move_and_slide()
	_update_animation(delta)
	_update_debug()
	AudioManager.update_surface_audio(velocity.length(), clampf(absf(lateral_slip) / 12.0, 0.0, 1.0), state == State.GRIND)
	telemetry_updated.emit(telemetry())

func _update_ground(delta: float) -> void:
	if not contact.grounded:
		coyote_remaining -= delta
		if coyote_remaining <= 0.0:
			_enter_air()
		return
	coyote_remaining = profile.coyote_time
	var normal := contact.average_normal
	var ski_forward := (-global_basis.z).slide(normal).normalized()
	var ski_right := ski_forward.cross(normal).normalized()
	var steer := InputManager.axis(&"steer_left", &"steer_right")
	braking = Input.is_action_pressed("brake")
	tuck_amount = 0.0 if braking else Input.get_action_strength("tuck")
	edge_amount = move_toward(edge_amount, steer, profile.edge_response * delta)

	# Gravity acts down the slope; friction is anisotropic along/across the skis.
	velocity += Vector3.DOWN.slide(normal) * profile.gravity * delta
	var longitudinal_speed := velocity.dot(ski_forward)
	lateral_slip = velocity.dot(ski_right)
	var speed_ratio := clampf(absf(longitudinal_speed) / 28.0, 0.0, 1.0)
	var grip := minf(profile.maximum_edge_grip, profile.lateral_friction + absf(edge_amount) * profile.maximum_edge_grip * speed_ratio)
	if braking:
		grip = profile.brake_friction
		longitudinal_speed = move_toward(longitudinal_speed, 0.0, profile.brake_friction * 0.4 * delta)
	var lateral_correction := minf(absf(lateral_slip), grip * delta) * signf(lateral_slip)
	velocity -= ski_right * lateral_correction
	carve_force = absf(lateral_correction) / maxf(delta, 0.001)

	var drag_multiplier := lerpf(1.0, profile.tuck_drag_multiplier, tuck_amount)
	var drag := profile.base_drag * drag_multiplier * velocity.length_squared()
	velocity -= velocity.normalized() * minf(drag * delta, velocity.length())
	velocity -= ski_forward * minf(absf(longitudinal_speed), profile.longitudinal_friction * delta) * signf(longitudinal_speed)
	if velocity.length() > profile.maximum_speed:
		velocity = velocity.limit_length(profile.maximum_speed)

	var steer_rate := lerpf(profile.low_speed_steering, profile.high_speed_steering, speed_ratio)
	if braking:
		steer_rate *= 1.45
	var yaw := -edge_amount * steer_rate * delta
	var turned_forward := ski_forward.rotated(normal, yaw)
	var target_basis := Basis.looking_at(turned_forward, normal).orthonormalized()
	global_basis = Basis(Quaternion(global_basis).slerp(Quaternion(target_basis), 1.0 - exp(-8.0 * delta)))

	if trick_command.phase == TrickCommand.PresentationPhase.SETUP:
		jump_charge = maxf(jump_charge, trick_command.gesture_strength * 0.32)
	if trick_command.pop_strength > 0.0:
		_pop(normal, trick_command.pop_strength, trick_command.rotation_impulse, trick_command.kind)
	elif Input.is_action_pressed("jump"):
		jump_charge = minf(jump_charge + delta, 0.32)
	if trick_command.pop_strength <= 0.0 and Input.is_action_just_released("jump"):
		_pop(normal)
	elif Input.is_action_just_pressed("jump") and last_physics_delta > 0.0:
		jump_charge = maxf(jump_charge, 0.06)

	AudioManager.skid_feedback(clampf(absf(lateral_slip) / 14.0 + (0.35 if braking else 0.0), 0.0, 1.0))
	spray.emitting = absf(lateral_slip) > 2.5 or braking

func _update_air(delta: float) -> void:
	air_time += delta
	braking = false
	tuck_amount = 0.0
	velocity += Vector3.DOWN * profile.gravity * delta
	if trick_command.committed:
		angular_velocity += trick_command.rotation_impulse
	angular_velocity.y += -trick_sample.left_stick.x * flick_profile.air_yaw_trim_acceleration * delta
	angular_velocity = angular_velocity.limit_length(profile.maximum_angular_speed)
	angular_velocity *= exp(-profile.air_angular_damping * delta)
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.BACK, angular_velocity.z * delta)
	trick.update_air(angular_velocity, delta, trick_command)
	spray.emitting = false
	_try_capture_rail()
	if contact.grounded and velocity.dot(contact.average_normal) < 0.0:
		_handle_landing()

func _update_grind(delta: float) -> void:
	if active_rail == null:
		_enter_air()
		return
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction
	rail_balance_input = trick_sample.left_stick.x
	var slope_acceleration := Vector3.DOWN.dot(tangent) * profile.gravity
	rail_speed = maxf(0.0, rail_speed + slope_acceleration * delta - (profile.rail_friction + active_rail.base_friction) * delta)
	rail_offset += rail_speed * rail_direction * delta
	if rail_offset <= 0.02 or rail_offset >= active_rail.path_length - 0.02 or rail_speed < 1.2:
		_exit_rail(false)
		return
	global_position = active_rail.sample_world(rail_offset)
	velocity = tangent * rail_speed
	var target_basis := Basis.looking_at(tangent, Vector3.UP)
	global_basis = Basis(Quaternion(global_basis).slerp(Quaternion(target_basis), 1.0 - exp(-12.0 * delta)))
	if trick_command.kind == TrickCommand.Kind.RAIL_SLIDE_LEFT:
		rail_pose = -1
	elif trick_command.kind == TrickCommand.Kind.RAIL_SLIDE_RIGHT:
		rail_pose = 1
	trick.update_grind(delta, rail_pose)
	AudioManager.rail_feedback(rail_speed)
	if trick_command.kind == TrickCommand.Kind.RAIL_POP or Input.is_action_just_pressed("jump"):
		_exit_rail(true)

func _update_bail(delta: float) -> void:
	braking = false
	bail_time -= delta
	velocity += Vector3.DOWN * profile.gravity * delta
	rotate_object_local(Vector3.BACK, delta * 2.8)
	if bail_time <= 0.0 and contact.grounded:
		SessionManager.request_respawn()

func _pop(normal: Vector3, requested_strength: float = -1.0, rotation_impulse: Vector3 = Vector3.ZERO, takeoff_kind: int = TrickCommand.Kind.POP) -> void:
	var strength := requested_strength if requested_strength >= 0.0 else lerpf(0.72, 1.0, clampf(jump_charge / 0.28, 0.0, 1.0))
	velocity += normal * profile.pop_impulse * strength
	animation_controller.trigger(SkierAnimationController.AnimationEvent.POP, strength)
	jump_charge = 0.0
	_enter_air(takeoff_kind)
	angular_velocity = (angular_velocity + rotation_impulse).limit_length(profile.maximum_angular_speed)

func _enter_air(takeoff_kind: int = TrickCommand.Kind.NONE) -> void:
	if state == State.AIR:
		return
	state = State.AIR
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	angular_velocity = Vector3.ZERO
	air_time = 0.0
	active_trick_kind = takeoff_kind
	trick.begin_air(velocity.dot(-global_basis.z) < 0.0, takeoff_kind)
	state_changed.emit("Air")

func _handle_landing() -> void:
	var result := LandingSolver.evaluate(global_basis.y, -global_basis.z, contact.average_normal, velocity, angular_velocity, profile)
	if int(result.outcome) != LandingSolver.Outcome.BAIL:
		var assisted_score := minf(1.0, float(result.score) + float(GameSettings.active.get("landing_assist", 0.35)) * 0.08)
		result.score = assisted_score
		if assisted_score >= profile.clean_threshold:
			result.outcome = LandingSolver.Outcome.CLEAN
		elif assisted_score >= profile.sketchy_threshold:
			result.outcome = LandingSolver.Outcome.SKETCHY
	AudioManager.landing_feedback(float(result.score), float(result.impact))
	landed.emit(result)
	if int(result.outcome) == LandingSolver.Outcome.BAIL:
		_bail()
		return
	var landing_event := SkierAnimationController.AnimationEvent.LAND_CLEAN
	if int(result.outcome) == LandingSolver.Outcome.SKETCHY:
		landing_event = SkierAnimationController.AnimationEvent.LAND_SKETCHY
	elif int(result.outcome) == LandingSolver.Outcome.HARD:
		landing_event = SkierAnimationController.AnimationEvent.LAND_HARD
	animation_controller.trigger(landing_event, clampf(float(result.impact) / profile.bail_impact_speed + 0.35, 0.35, 1.25), signf(lateral_slip))
	var quality := float(result.score)
	if int(result.outcome) == LandingSolver.Outcome.SKETCHY:
		velocity *= 0.78
	elif int(result.outcome) == LandingSolver.Outcome.HARD:
		velocity *= 0.48
	var projected_forward := (-global_basis.z).slide(contact.average_normal).normalized()
	global_basis = Basis.looking_at(projected_forward, contact.average_normal)
	angular_velocity = Vector3.ZERO
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	state = State.GROUND
	trick.land(quality, velocity.dot(-global_basis.z) < 0.0)
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	rail_pose = 0
	state_changed.emit("Ground")

func _try_capture_rail() -> void:
	if velocity.y > 3.0:
		return
	var best: Dictionary = {"valid": false, "distance": INF}
	var best_rail: GrindRail3D
	for node: Node in get_tree().get_nodes_in_group("grind_rails"):
		var rail := node as GrindRail3D
		var candidate := rail.capture_candidate(global_position, velocity, profile.rail_capture_radius, profile.rail_min_speed)
		if bool(candidate.get("valid", false)) and float(candidate.distance) < float(best.distance):
			best = candidate
			best_rail = rail
	if best_rail != null:
		active_rail = best_rail
		rail_offset = float(best.offset)
		rail_direction = float(best.direction)
		rail_speed = float(best.speed)
		state = State.GRIND
		rail_pose = 0
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		global_position = best.position as Vector3
		animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, clampf(rail_speed / 20.0, 0.25, 1.0), rail_direction)
		state_changed.emit("Grind")

func _exit_rail(pop_off: bool) -> void:
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction if active_rail != null else -global_basis.z
	velocity = tangent * rail_speed
	if pop_off:
		velocity += Vector3.UP * profile.pop_impulse * 0.72
	animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, clampf(rail_speed / 20.0, 0.25, 1.0), rail_direction)
	active_rail = null
	_enter_air(TrickCommand.Kind.POP if pop_off else TrickCommand.Kind.NONE)

func _bail() -> void:
	state = State.BAIL
	bail_time = 1.0
	trick.reset()
	flick.reset()
	AudioManager.crash_feedback()
	animation_controller.trigger(SkierAnimationController.AnimationEvent.BAIL, 1.0, signf(lateral_slip))
	crashed.emit()
	state_changed.emit("Bail")

func respawn_at(value: Transform3D) -> void:
	active_rail = null
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = value
	global_position += Vector3.UP * 0.35
	state = State.AIR
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	trick.reset()
	flick.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	rail_pose = 0
	AudioManager.stop_feedback()
	animation_controller.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
	state_changed.emit("Air")

func telemetry() -> Dictionary:
	return {
		"speed_mps": velocity.length(),
		"speed_kph": velocity.length() * 3.6,
		"state": State.keys()[state],
		"grounded": contact.grounded,
		"contact_confidence": contact.confidence,
		"surface_normal": contact.average_normal,
		"edge": edge_amount,
		"lateral_slip": lateral_slip,
		"carve_force": carve_force,
		"angular_velocity": angular_velocity,
		"rail": active_rail.name if active_rail != null else "—",
		"flick": {
			"stick": trick_sample.right_stick,
			"kind": TrickCommand.Kind.keys()[active_trick_kind],
			"phase": TrickCommand.PresentationPhase.keys()[trick_phase],
			"strength": gesture_strength,
			"left_trigger": trick_sample.left_trigger,
			"right_trigger": trick_sample.right_trigger,
			"grab": TrickController.GRAB_NAMES[trick.grab_pose],
		},
		"animation": animation_controller.debug_snapshot() if animation_controller != null else {},
	}

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.43
	capsule.height = 1.72
	shape.shape = capsule
	shape.position.y = 0.92
	add_child(shape)
	animation_controller = SkierAnimationController.new()
	animation_controller.name = "SkierAnimationController"
	visual_root = animation_controller
	add_child(animation_controller)

func _build_spray() -> void:
	spray = GPUParticles3D.new()
	spray.amount = 80
	spray.lifetime = 0.65
	spray.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.75, 0.6)
	process_material.spread = 55.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 7.0
	process_material.gravity = Vector3(0.0, -7.0, 0.0)
	process_material.scale_min = 0.04
	process_material.scale_max = 0.12
	spray.process_material = process_material
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.08, 0.08)
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = Color(0.9, 0.96, 1.0, 0.75)
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_mesh.material = particle_material
	spray.draw_pass_1 = particle_mesh
	spray.position = Vector3(0.0, 0.15, 0.55)
	add_child(spray)

func _build_debug_draw() -> void:
	debug_mesh = ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = debug_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#3affd0")
	instance.material_override = material
	add_child(instance)

func _sample_trick_input(delta: float) -> void:
	trick_sample.right_stick = InputManager.vector(&"trick_left", &"trick_right", &"trick_up", &"trick_down")
	trick_sample.left_stick = Vector2(InputManager.axis(&"steer_left", &"steer_right"), 0.0)
	trick_sample.left_trigger = Input.get_action_strength("grab_left")
	trick_sample.right_trigger = Input.get_action_strength("grab_right")
	trick_sample.keyboard_pop_pressed = Input.is_action_pressed("jump")
	trick_sample.keyboard_pop_released = Input.is_action_just_released("jump")
	var previous_grab := grab_amount
	trick_command = flick.step(trick_sample, _flick_context(), delta)
	gesture_strength = trick_command.gesture_strength if trick_command.gesture_strength > 0.0 else move_toward(gesture_strength, 0.0, delta * 3.0)
	grab_amount = trick_command.grab_amount
	grab_tweak = trick_command.grab_tweak
	if trick_command.committed and trick_command.kind not in [TrickCommand.Kind.NONE, TrickCommand.Kind.POP, TrickCommand.Kind.RAIL_POP, TrickCommand.Kind.RAIL_SLIDE_LEFT, TrickCommand.Kind.RAIL_SLIDE_RIGHT]:
		active_trick_kind = trick_command.kind
	if previous_grab > 0.0 and grab_amount <= 0.0 and state == State.AIR:
		grab_release_time = 0.22
	else:
		grab_release_time = maxf(0.0, grab_release_time - delta)
	trick_phase = trick_command.phase
	if state == State.AIR and trick_phase == TrickCommand.PresentationPhase.NEUTRAL:
		if grab_release_time > 0.0:
			trick_phase = TrickCommand.PresentationPhase.OPEN
		elif active_trick_kind != TrickCommand.Kind.NONE and angular_velocity.length() > 0.2:
			trick_phase = TrickCommand.PresentationPhase.ROTATE

func _flick_context() -> int:
	match state:
		State.GROUND: return FlickTrickInterpreter.Context.GROUND
		State.AIR: return FlickTrickInterpreter.Context.AIR
		State.GRIND: return FlickTrickInterpreter.Context.GRIND
	return FlickTrickInterpreter.Context.BAIL

func _update_animation(delta: float) -> void:
	var predicted_landing := _predict_landing_time()
	var landing_release := 0.0
	if predicted_landing >= 0.0 and predicted_landing < animation_controller.profile.landing_anticipation_time:
		landing_release = 1.0 - predicted_landing / animation_controller.profile.landing_anticipation_time
	animation_frame.locomotion_state = state
	animation_frame.speed_mps = velocity.length()
	animation_frame.speed_ratio = clampf(velocity.length() / profile.maximum_speed, 0.0, 1.0)
	animation_frame.edge = edge_amount
	animation_frame.skid = lateral_slip
	animation_frame.carve_force = carve_force
	animation_frame.tuck = tuck_amount
	animation_frame.braking = braking
	animation_frame.compression = clampf(jump_charge / 0.32, 0.0, 1.0)
	animation_frame.contact_confidence = contact.confidence
	animation_frame.ground_normal = contact.average_normal
	animation_frame.angular_velocity = angular_velocity
	animation_frame.vertical_velocity = velocity.y
	animation_frame.air_time = air_time
	animation_frame.predicted_landing_time = predicted_landing
	animation_frame.grab_pose = trick.grab_pose
	animation_frame.switch_stance = velocity.dot(-global_basis.z) < 0.0
	animation_frame.rail_speed = rail_speed if state == State.GRIND else 0.0
	animation_frame.rail_balance = (float(rail_pose) if rail_pose != 0 else rail_balance_input) if state == State.GRIND else 0.0
	animation_frame.rail_type = active_rail.rail_type if active_rail != null else 0
	animation_frame.trick_kind = active_trick_kind
	animation_frame.trick_phase = TrickCommand.PresentationPhase.LANDING if landing_release > 0.58 else trick_phase
	animation_frame.gesture_strength = gesture_strength
	animation_frame.gesture_direction = trick_sample.right_stick
	animation_frame.left_trigger = trick_sample.left_trigger
	animation_frame.right_trigger = trick_sample.right_trigger
	animation_frame.grab_amount = grab_amount * (1.0 - landing_release)
	animation_frame.grab_tweak = grab_tweak
	var rotation_amount := maxf(absf(trick.accumulated_rotation.x), maxf(absf(trick.accumulated_rotation.y), absf(trick.accumulated_rotation.z)))
	animation_frame.rotation_progress = fmod(rotation_amount / TAU, 1.0)
	animation_controller.apply_frame(animation_frame, delta)

func _predict_landing_time() -> float:
	if state != State.AIR or velocity.y > 1.0:
		return -1.0
	var origin := global_position + Vector3.UP * 0.2
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 12.0, 0b101)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	var distance := origin.distance_to(hit.position as Vector3)
	return clampf(distance / maxf(2.0, -velocity.y), 0.0, 2.0)

func _update_debug() -> void:
	debug_mesh.clear_surfaces()
	if not debug_enabled:
		return
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point: Vector3 in contact.hit_points:
		var local := to_local(point)
		debug_mesh.surface_add_vertex(local)
		debug_mesh.surface_add_vertex(local + contact.average_normal * 1.2)
	debug_mesh.surface_add_vertex(Vector3.UP)
	debug_mesh.surface_add_vertex(Vector3.UP + to_local(global_position + velocity * 0.15))
	debug_mesh.surface_end()

var last_physics_delta: float:
	get:
		return 1.0 / float(Engine.physics_ticks_per_second)
