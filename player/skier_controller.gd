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
var pressure_amount := 0.0
var lateral_slip := 0.0
var carve_force := 0.0
var steering_input_raw := 0.0
var steering_input := 0.0
var brake_amount := 0.0
var effective_steer_rate := 0.0
var available_grip := 0.0
var centripetal_demand := 0.0
var current_carve_ratio := 1.0
var skid_amount := 0.0
var heading_travel_angle_degrees := 0.0
var slope_angle_degrees := 0.0
var coyote_remaining := 0.0
var jump_charge := 0.0
var tuck_amount := 0.0
var braking := false
var air_time := 0.0
var rail_balance_input := 0.0
var rail_balance := 0.0
var active_rail: GrindRail3D
var rail_offset := 0.0
var rail_direction := 1.0
var rail_speed := 0.0
var rail_prev_tangent := Vector3.ZERO
var rail_capture_from_position := Vector3.ZERO
var rail_capture_blend_remaining := 0.0
var bail_time := 0.0
var bail_recovering := false
var debug_enabled := false
var trick: TrickController
var scoring: RunScoring
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
var predicted_landing_time := -1.0
var landing_feedback_armed := false
var air_deliberate := false
var wall_pin_time := 0.0
var last_collision_diagnostics: Array[Dictionary] = []
var last_collision_colliders: Array[String] = []
var last_speed_discontinuity: Dictionary = {}

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.42
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_build_body()
	_build_spray()
	_build_debug_draw()
	trick = TrickController.new()
	add_child(trick)
	scoring = RunScoring.new()
	scoring.name = "RunScoring"
	add_child(scoring)
	trick.trick_landed.connect(scoring.accept_trick)
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
	var velocity_before_motion := velocity
	last_collision_diagnostics.clear()
	last_collision_colliders.clear()
	last_speed_discontinuity = {}
	contact.sample(self, 1.45, profile.ground_probe_reach)
	contact.merge_capsule_floor(is_on_floor(), get_floor_normal())
	_sample_trick_input(delta)
	match state:
		State.GROUND: _update_ground(delta)
		State.AIR: _update_air(delta)
		State.GRIND: _update_grind(delta)
		State.BAIL: _update_bail(delta)
	if state != State.GRIND:
		move_and_slide()
		_record_motion_diagnostics(velocity_before_motion)
		if state == State.GROUND and contact.grounded:
			_suppress_into_slope_bounce()
			_update_wall_pin(delta)
	scoring.step(delta, velocity.length())
	_update_animation(delta)
	_update_debug()
	AudioManager.update_surface_audio(velocity.length(), skid_amount, state == State.GRIND, contact.surface_kind, state == State.AIR)
	telemetry_updated.emit(telemetry())

func _update_ground(delta: float) -> void:
	if not contact.grounded:
		coyote_remaining -= delta
		if coyote_remaining <= 0.0:
			_enter_air()
			return
	else:
		coyote_remaining = profile.coyote_time
	var normal := contact.average_normal
	var forward_on_slope := (-global_basis.z).slide(normal)
	if forward_on_slope.length_squared() < 0.0001:
		forward_on_slope = contact.downhill()
	if forward_on_slope.length_squared() < 0.0001:
		return
	var ski_forward := forward_on_slope.normalized()
	steering_input_raw = InputManager.raw_axis(&"steer_left", &"steer_right")
	steering_input = InputManager.axis(&"steer_left", &"steer_right")
	var steer := steering_input
	pressure_amount = InputManager.axis(&"steer_back", &"steer_forward")
	brake_amount = Input.get_action_strength("brake")
	braking = brake_amount > 0.01
	tuck_amount = 0.0 if braking else Input.get_action_strength("tuck")
	var edge_rate := profile.edge_response if absf(steer) >= absf(edge_amount) - 0.001 else profile.edge_release
	edge_amount = move_toward(edge_amount, steer, edge_rate * delta)

	# Gravity acts down the slope; friction is anisotropic along/across the skis.
	velocity += Vector3.DOWN.slide(normal) * profile.gravity * delta
	# Ski suspension: on convex crests and raised decks the skis lose capsule
	# support, so pull the body toward the snow when the probes sit above the
	# seat height. The pull aims at the average terrain contact point (not
	# straight down the normal), so approaching a deck lip or berm edge gains a
	# forward-up component that rides the step instead of dead-stopping on it.
	# One-sided only; the capsule enforces the hard floor and
	# _suppress_into_slope_bounce damps the approach so this cannot pogo.
	# Probe rays start 0.35 m above the body origin (see SkiContactSolver).
	if contact.grounded and contact.hit_points.size() > 0:
		var seat_distance := 0.35 + profile.ground_attach_height
		var attach_gap := contact.average_distance - seat_distance
		if attach_gap > 0.0:
			var probe_origin := global_position + normal * 0.35
			var seat_direction := (contact.average_hit_position - probe_origin).normalized()
			velocity += seat_direction * minf(attach_gap * profile.ground_attach_stiffness, profile.ground_attach_max_accel) * delta
	var fall_line := contact.downhill()
	var planar := velocity.slide(normal)
	var planar_speed := planar.length()
	slope_angle_degrees = rad_to_deg(acos(clampf(normal.normalized().dot(Vector3.UP), -1.0, 1.0)))
	var pointing_downhill := maxf(0.0, ski_forward.dot(fall_line))
	var pressure_glide := 1.0 + maxf(0.0, pressure_amount) * profile.pressure_glide_gain * 0.15
	if not braking and pointing_downhill > 0.0:
		velocity += ski_forward * (pointing_downhill * profile.glide_acceleration * pressure_glide * delta)
		planar = velocity.slide(normal)
		planar_speed = planar.length()
	var speed_ratio := clampf(planar_speed / maxf(profile.steering_speed_reference, 1.0), 0.0, 1.0)
	var surface_grip := _surface_grip_multiplier()
	var surface_drag := _surface_drag_multiplier()
	var steer_rate := lerpf(profile.low_speed_steering, profile.high_speed_steering, speed_ratio)
	var speed_gate := clampf(planar_speed / maxf(profile.full_steer_speed, 1.0), profile.minimum_steer_speed_gate, 1.0)
	if braking:
		steer_rate *= lerpf(1.0, profile.brake_steer_multiplier, brake_amount)
		speed_gate = lerpf(speed_gate, 1.0, brake_amount)
	steer_rate *= speed_gate * lerpf(1.0, profile.tuck_steering_multiplier, tuck_amount)
	effective_steer_rate = steer_rate + planar_speed * profile.sidecut
	var requested_yaw := -edge_amount * effective_steer_rate * delta
	var needed_centripetal := planar_speed * absf(edge_amount) * effective_steer_rate
	centripetal_demand = needed_centripetal
	var tip_scale := clampf(1.0 + (contact.tip_load + pressure_amount * 0.35) * profile.tip_grip_gain, 0.7, 1.22)
	tip_scale *= clampf(1.0 + pressure_amount * profile.pressure_grip_gain, 0.78, 1.28)
	var grip := (profile.lateral_friction + absf(edge_amount) * profile.maximum_edge_grip * lerpf(0.82, 1.0, speed_ratio)) * surface_grip
	grip *= tip_scale
	if braking:
		grip = lerpf(grip, maxf(grip, profile.brake_friction), brake_amount)
	available_grip = grip
	var carve_ratio := 1.0 if needed_centripetal <= 0.05 else clampf(grip / needed_centripetal, 0.0, 1.0)
	current_carve_ratio = carve_ratio
	var velocity_yaw := requested_yaw * carve_ratio
	if planar_speed > 0.08:
		var rotated := planar.rotated(normal, velocity_yaw)
		if carve_ratio < 1.0:
			rotated = rotated.move_toward(Vector3.ZERO, (1.0 - carve_ratio) * profile.skid_friction * delta)
		velocity = rotated + normal * velocity.dot(normal)
	var heading_yaw := requested_yaw
	if absf(edge_amount) < profile.weathervane_edge and planar_speed > 0.4:
		var travel := velocity.slide(normal).normalized()
		if ski_forward.dot(travel) < 0.0:
			travel = -travel
		var align := ski_forward.signed_angle_to(travel, normal)
		var vane := 1.0 - absf(edge_amount) / maxf(profile.weathervane_edge, 0.001)
		heading_yaw += clampf(align, -profile.weathervane_rate * vane * delta, profile.weathervane_rate * vane * delta)
	var turned_forward := ski_forward.rotated(normal, heading_yaw).normalized()
	turned_forward = _constrain_heading_to_travel(turned_forward, normal, speed_ratio, delta)
	var turned_right := turned_forward.cross(normal).normalized()
	lateral_slip = velocity.dot(turned_right)
	var travel_for_angle := velocity.slide(normal)
	if travel_for_angle.length_squared() > 0.01:
		travel_for_angle = travel_for_angle.normalized()
		if turned_forward.dot(travel_for_angle) < 0.0:
			travel_for_angle = -travel_for_angle
		heading_travel_angle_degrees = rad_to_deg(travel_for_angle.signed_angle_to(turned_forward, normal))
	else:
		heading_travel_angle_degrees = 0.0
	var unused_grip := maxf(0.0, grip - needed_centripetal)
	var tracking := minf(absf(lateral_slip), unused_grip * delta) * signf(lateral_slip)
	velocity -= turned_right * tracking
	carve_force = planar_speed * absf(velocity_yaw) / maxf(delta, 0.001)
	skid_amount = clampf(
		(1.0 - current_carve_ratio) * absf(edge_amount)
		+ absf(lateral_slip) / 12.0
		+ brake_amount * 0.35,
		0.0,
		1.0
	)
	if braking:
		var longitudinal_speed := velocity.dot(turned_forward)
		var brake_step := profile.brake_friction * profile.brake_speed_scrub_multiplier * brake_amount * delta
		velocity -= turned_forward * (longitudinal_speed - move_toward(longitudinal_speed, 0.0, brake_step))

	var drag_multiplier := lerpf(1.0, profile.tuck_drag_multiplier, tuck_amount)
	var drag := profile.base_drag * surface_drag * drag_multiplier * velocity.length_squared()
	if velocity.length_squared() > 0.0001:
		velocity -= velocity.normalized() * minf(drag * delta, velocity.length())
	var glide_speed := velocity.dot(turned_forward)
	velocity -= turned_forward * minf(absf(glide_speed), profile.longitudinal_friction * surface_drag * delta) * signf(glide_speed)
	if velocity.length() > profile.maximum_speed:
		velocity = velocity.limit_length(profile.maximum_speed)

	# Apply responsive turn yaw, with a soft high-speed slip-angle limit; only terrain alignment is smoothed.
	var current_up := global_basis.y.normalized() if global_basis.y.length_squared() > 0.0001 else normal
	var surface_up := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	# Normalized lerp avoids Vector3.slerp's axis-normalization error for nearly parallel normals.
	var aligned_up := current_up.lerp(surface_up, 1.0 - exp(-profile.ground_align_rate * delta)).normalized()
	if absf(aligned_up.dot(turned_forward)) > 0.92:
		aligned_up = normal
	global_basis = Basis.looking_at(turned_forward.normalized(), aligned_up).orthonormalized()

	if trick_command.phase == TrickCommand.PresentationPhase.SETUP:
		jump_charge = maxf(jump_charge, trick_command.gesture_strength * profile.maximum_jump_charge)
	if trick_command.pop_strength > 0.0:
		_pop(normal, trick_command.pop_strength, trick_command.rotation_impulse, trick_command.kind)
	elif Input.is_action_pressed("jump"):
		jump_charge = minf(jump_charge + delta, profile.maximum_jump_charge)
	if trick_command.pop_strength <= 0.0 and Input.is_action_just_released("jump"):
		_pop(normal)
	elif Input.is_action_just_pressed("jump") and last_physics_delta > 0.0:
		jump_charge = maxf(jump_charge, 0.06)

	AudioManager.skid_feedback(skid_amount)
	spray.amount_ratio = clampf((skid_amount - 0.15) / 0.85, 0.0, 1.0)
	spray.emitting = skid_amount > 0.2

func _constrain_heading_to_travel(candidate: Vector3, normal: Vector3, speed_ratio: float, delta: float) -> Vector3:
	var travel := velocity.slide(normal)
	if travel.length_squared() <= 0.01:
		return candidate
	travel = travel.normalized()
	if candidate.dot(travel) < 0.0:
		travel = -travel
	var maximum_angle := deg_to_rad(lerpf(
		profile.low_speed_heading_travel_limit_degrees,
		profile.high_speed_heading_travel_limit_degrees,
		speed_ratio
	))
	var signed_angle := travel.signed_angle_to(candidate, normal)
	var excess := absf(signed_angle) - maximum_angle
	if excess <= 0.0:
		return candidate
	var correction := minf(excess, profile.heading_travel_limit_response * delta)
	return candidate.rotated(normal, -signf(signed_angle) * correction).normalized()

func _update_air(delta: float) -> void:
	air_time += delta
	braking = false
	brake_amount = 0.0
	skid_amount = 0.0
	tuck_amount = 0.0
	velocity += Vector3.DOWN * profile.air_gravity * delta
	velocity.y = maxf(velocity.y, -profile.air_terminal_speed)
	if trick_command.committed:
		angular_velocity += trick_command.rotation_impulse
	angular_velocity.y += -trick_sample.left_stick.x * flick_profile.air_yaw_trim_acceleration * delta
	angular_velocity.x += -trick_sample.left_stick.y * profile.air_flip_trim_acceleration * delta
	angular_velocity = angular_velocity.limit_length(profile.maximum_angular_speed)
	var damping := profile.air_angular_damping
	var predicted := _predict_landing_time()
	var landing_assist := float(GameSettings.active.get("landing_assist", 0.35))
	var actively_rotating := trick_sample.left_stick.length() > 0.2 or trick_sample.right_stick.length() > flick_profile.center_reset_threshold or grab_amount > 0.05
	if not actively_rotating and predicted >= 0.0 and predicted < profile.air_landing_window:
		var landing_proximity := 1.0 - predicted / maxf(profile.air_landing_window, 0.01)
		damping = lerpf(damping, profile.air_landing_damping, landing_proximity * landing_assist)
	angular_velocity *= exp(-damping * delta)
	global_basis = global_basis.orthonormalized()
	rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
	rotate_object_local(Vector3.UP, angular_velocity.y * delta)
	rotate_object_local(Vector3.BACK, angular_velocity.z * delta)
	global_basis = global_basis.orthonormalized()
	trick.update_air(angular_velocity, delta, trick_command)
	spray.emitting = false
	_try_capture_rail()
	if state != State.AIR:
		return
	if contact.grounded and air_time >= profile.min_air_time and velocity.dot(contact.average_normal) < 1.5:
		if air_deliberate:
			_handle_landing()
		else:
			# Terrain hop (crest, deck lip, spawn seat): rejoin the snow without
			# presenting a jump landing.
			_reseat_on_snow()

func _update_grind(delta: float) -> void:
	if active_rail == null:
		_enter_air()
		return
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction
	rail_balance_input = trick_sample.left_stick.x
	brake_amount = 0.0
	skid_amount = 0.0
	var slope_acceleration := Vector3.DOWN.dot(tangent) * profile.gravity
	rail_speed += slope_acceleration * delta
	rail_speed = move_toward(rail_speed, 0.0, (profile.rail_friction + active_rail.base_friction) * delta)
	# Allow reverse travel on uphill / rainbow features instead of dying at a stop.
	if absf(rail_speed) < 0.35 and absf(slope_acceleration) > 1.0:
		rail_speed = signf(slope_acceleration) * 0.35
	rail_offset += rail_speed * rail_direction * delta
	if rail_offset <= 0.02 or rail_offset >= active_rail.path_length - 0.02:
		_exit_rail(false)
		return
	# Balance: left stick counters drift; kinks and boardslides add instability.
	var kink := 0.0
	if rail_prev_tangent.length_squared() > 0.01:
		kink = 1.0 - clampf(rail_prev_tangent.normalized().dot(tangent.normalized()), 0.0, 1.0)
	rail_prev_tangent = tangent
	var boardslide_factor := 1.0 + absf(float(rail_pose)) * profile.rail_boardslide_instability
	var drift := (profile.rail_balance_drift + kink * profile.rail_kink_instability) * boardslide_factor
	if absf(rail_balance) > 0.08:
		rail_balance += signf(rail_balance) * drift * delta
	else:
		rail_balance += active_rail.drift_bias * drift * delta
	rail_balance += -rail_balance_input * profile.rail_balance_input_gain * delta
	rail_balance = clampf(rail_balance, -1.35, 1.35)
	if absf(rail_balance) >= profile.rail_balance_fail:
		_slip_off_rail()
		return
	var rail_target := active_rail.sample_world(rail_offset)
	if rail_capture_blend_remaining > 0.0:
		rail_capture_blend_remaining = maxf(0.0, rail_capture_blend_remaining - delta)
		var blend_progress := 1.0 - rail_capture_blend_remaining / maxf(profile.rail_capture_blend_time, 0.01)
		blend_progress = blend_progress * blend_progress * (3.0 - 2.0 * blend_progress)
		global_position = rail_capture_from_position.lerp(rail_target, blend_progress)
	else:
		global_position = rail_target
	velocity = tangent * rail_speed
	var look_tangent := tangent if rail_speed >= 0.0 else -tangent
	if look_tangent.length_squared() < 0.0001:
		look_tangent = tangent
	var target_basis := Basis.looking_at(look_tangent, Vector3.UP)
	global_basis = Basis(Quaternion(global_basis).slerp(Quaternion(target_basis), 1.0 - exp(-profile.rail_alignment_rate * delta)))
	if trick_command.kind == TrickCommand.Kind.RAIL_SLIDE_LEFT:
		rail_pose = -1
	elif trick_command.kind == TrickCommand.Kind.RAIL_SLIDE_RIGHT:
		rail_pose = 1
	trick.update_grind(delta, rail_pose)
	AudioManager.rail_feedback(absf(rail_speed))
	if trick_command.kind == TrickCommand.Kind.RAIL_POP or Input.is_action_just_pressed("jump"):
		_exit_rail(true)

func _update_bail(delta: float) -> void:
	braking = false
	brake_amount = 0.0
	skid_amount = 0.0
	bail_time -= delta
	velocity += Vector3.DOWN * profile.air_gravity * delta
	if contact.grounded:
		velocity = velocity.slide(contact.average_normal)
		velocity *= exp(-profile.bail_ground_damping * delta)
		var aligned_up := global_basis.y.lerp(contact.average_normal, 1.0 - exp(-profile.bail_ground_align_rate * delta)).normalized()
		var forward := (-global_basis.z).slide(contact.average_normal)
		if forward.length_squared() < 0.0001:
			forward = contact.downhill()
		if forward.length_squared() > 0.0001:
			global_basis = Basis.looking_at(forward.normalized(), aligned_up)
	else:
		rotate_object_local(Vector3.BACK, delta * profile.bail_air_tumble_rate)
	if bail_time <= 0.0 and contact.grounded:
		_recover_from_bail()

func _pop(normal: Vector3, requested_strength: float = -1.0, rotation_impulse: Vector3 = Vector3.ZERO, takeoff_kind: int = TrickCommand.Kind.POP) -> void:
	var normalized_charge := clampf(jump_charge / maxf(profile.maximum_jump_charge, 0.001), 0.0, 1.0)
	var strength := requested_strength if requested_strength >= 0.0 else lerpf(profile.minimum_pop_strength, 1.0, normalized_charge)
	velocity += normal * profile.pop_impulse * strength
	AudioManager.pop_feedback(strength)
	animation_controller.trigger(SkierAnimationController.AnimationEvent.POP, strength)
	jump_charge = 0.0
	_enter_air(takeoff_kind)
	air_deliberate = true
	angular_velocity = (angular_velocity + rotation_impulse).limit_length(profile.maximum_angular_speed)

func _enter_air(takeoff_kind: int = TrickCommand.Kind.NONE) -> void:
	if state == State.AIR:
		return
	state = State.AIR
	air_deliberate = false
	landing_feedback_armed = true
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	angular_velocity = Vector3.ZERO
	air_time = 0.0
	active_trick_kind = takeoff_kind
	trick.begin_air(velocity.dot(-global_basis.z) < 0.0, takeoff_kind)
	state_changed.emit("Air")

func _handle_landing() -> void:
	var result := LandingSolver.evaluate(global_basis.y, -global_basis.z, contact.average_normal, velocity, angular_velocity, profile)
	if int(result.outcome) != LandingSolver.Outcome.BAIL:
		var assisted_score := minf(1.0, float(result.score) + float(GameSettings.active.get("landing_assist", 0.35)) * 0.06)
		result.score = assisted_score
		if assisted_score >= profile.clean_threshold and float(result.upright_dot) >= profile.clean_upright_dot and float(result.impact) <= profile.bail_impact_speed * profile.clean_impact_ratio:
			result.outcome = LandingSolver.Outcome.CLEAN
		elif assisted_score >= profile.sketchy_threshold and float(result.upright_dot) >= profile.sketchy_upright_dot and float(result.impact) <= profile.bail_impact_speed * profile.sketchy_impact_ratio:
			result.outcome = LandingSolver.Outcome.SKETCHY
	var should_present_landing := landing_feedback_armed
	landing_feedback_armed = false
	if should_present_landing:
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
	velocity = velocity.slide(contact.average_normal)
	if int(result.outcome) == LandingSolver.Outcome.SKETCHY:
		velocity *= profile.sketchy_landing_speed_retain
	elif int(result.outcome) == LandingSolver.Outcome.HARD:
		velocity *= profile.hard_landing_speed_retain
	var projected_forward := (-global_basis.z).slide(contact.average_normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = contact.downhill()
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD
	global_basis = Basis.looking_at(projected_forward.normalized(), contact.average_normal.normalized()).orthonormalized()
	angular_velocity = Vector3.ZERO
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	state = State.GROUND
	if trick.had_trick_intent:
		scoring.begin_feature("jump")
	trick.land(quality, velocity.dot(-global_basis.z) < 0.0)
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	rail_pose = 0
	state_changed.emit("Ground")

func _suppress_into_slope_bounce() -> void:
	var into := velocity.dot(contact.average_normal)
	# Allow a small controlled approach speed so the suspension can seat the skis
	# quickly; anything harder than that would bounce or bury.
	if into < -profile.seat_approach_speed:
		velocity -= contact.average_normal * (into + profile.seat_approach_speed)

func _update_wall_pin(delta: float) -> void:
	# Safety net: wedged against an obstacle (deck wall, feature corner) with no
	# room to accelerate — hop up and over instead of standing stuck forever.
	if get_slide_collision_count() == 0 or velocity.length() > 1.2:
		wall_pin_time = 0.0
		return
	wall_pin_time += delta
	if wall_pin_time < 0.3:
		return
	wall_pin_time = 0.0
	var hop := contact.average_normal * 6.5
	var forward := (-global_basis.z).slide(contact.average_normal)
	if forward.length_squared() > 0.01:
		hop += forward.normalized() * 2.0
	velocity += hop

func _reseat_on_snow() -> void:
	velocity = velocity.slide(contact.average_normal)
	angular_velocity = Vector3.ZERO
	var projected_forward := (-global_basis.z).slide(contact.average_normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = contact.downhill()
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD
	global_basis = Basis.looking_at(projected_forward.normalized(), contact.average_normal.normalized()).orthonormalized()
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	state = State.GROUND
	state_changed.emit("Ground")

func _try_capture_rail() -> void:
	if velocity.y > 3.0:
		return
	var best: Dictionary = {"valid": false, "distance": INF}
	var best_rail: GrindRail3D
	for node: Node in get_tree().get_nodes_in_group("grind_rails"):
		var rail := node as GrindRail3D
		var candidate := rail.capture_candidate(global_position, velocity, profile.rail_capture_radius, profile.rail_min_speed)
		if bool(candidate.get("valid", false)) and float(candidate.distance) <= profile.rail_capture_max_snap and float(candidate.distance) < float(best.distance):
			best = candidate
			best_rail = rail
	if best_rail != null:
		active_rail = best_rail
		rail_offset = float(best.offset)
		rail_direction = float(best.direction)
		rail_speed = float(best.speed)
		var lateral_bias := clampf(float(best.get("signed_lateral", 0.0)) / maxf(best_rail.capture_radius, 0.1), -1.0, 1.0)
		rail_balance = lateral_bias * 0.18
		rail_prev_tangent = best.tangent as Vector3
		rail_capture_from_position = global_position
		rail_capture_blend_remaining = profile.rail_capture_blend_time
		state = State.GRIND
		rail_pose = 0
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, clampf(absf(rail_speed) / 20.0, 0.25, 1.0), rail_direction)
		state_changed.emit("Grind")

func _exit_rail(pop_off: bool) -> void:
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction if active_rail != null else -global_basis.z
	velocity = tangent * rail_speed
	if pop_off:
		velocity += Vector3.UP * profile.pop_impulse * profile.rail_pop_strength
	animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, clampf(absf(rail_speed) / 20.0, 0.25, 1.0), rail_direction)
	if trick.grind_seconds > 0.05:
		scoring.begin_feature("rail")
		trick.land(0.85, false)
	active_rail = null
	rail_balance = 0.0
	rail_capture_blend_remaining = 0.0
	_enter_air(TrickCommand.Kind.POP if pop_off else TrickCommand.Kind.NONE)
	air_deliberate = pop_off

func _slip_off_rail() -> void:
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction if active_rail != null else -global_basis.z
	var sideways := Vector3.UP.cross(tangent).normalized()
	if sideways.length_squared() < 0.01:
		sideways = global_basis.x
	velocity = (
		tangent * rail_speed * profile.rail_slip_speed_retain
		+ sideways * signf(rail_balance) * profile.rail_slip_lateral_speed
		+ Vector3.UP * profile.rail_slip_upward_speed
	)
	animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, 0.45, signf(rail_balance))
	active_rail = null
	rail_balance = 0.0
	rail_capture_blend_remaining = 0.0
	scoring.reset_link()
	_enter_air()

func _bail() -> void:
	state = State.BAIL
	bail_time = profile.bail_tumble_time
	bail_recovering = true
	velocity *= profile.bail_speed_retain
	angular_velocity = Vector3.ZERO
	scoring.bail()
	trick.reset()
	flick.reset()
	AudioManager.crash_feedback()
	animation_controller.trigger(SkierAnimationController.AnimationEvent.BAIL, 1.0, signf(lateral_slip))
	crashed.emit()
	state_changed.emit("Bail")

func _recover_from_bail() -> void:
	bail_recovering = false
	velocity = velocity.slide(contact.average_normal) * profile.bail_recovery_speed_retain
	angular_velocity = Vector3.ZERO
	var projected_forward := (-global_basis.z).slide(contact.average_normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = contact.downhill()
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD
	global_basis = Basis.looking_at(projected_forward.normalized(), contact.average_normal.normalized()).orthonormalized()
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	state = State.GROUND
	animation_controller.trigger(SkierAnimationController.AnimationEvent.RESPAWN, 0.55)
	state_changed.emit("Ground")

func respawn_at(value: Transform3D) -> void:
	active_rail = null
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = value
	global_position += Vector3.UP * 0.35
	state = State.AIR
	air_deliberate = false
	wall_pin_time = 0.0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	trick.reset()
	flick.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	rail_pose = 0
	rail_balance = 0.0
	rail_capture_blend_remaining = 0.0
	bail_recovering = false
	landing_feedback_armed = false
	scoring.reset_link()
	AudioManager.stop_feedback()
	animation_controller.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
	state_changed.emit("Air")

func reset_for_benchmark(value: Transform3D, initial_velocity: Vector3 = Vector3.ZERO) -> void:
	"""Reset every motion subsystem to a reproducible benchmark baseline."""
	active_rail = null
	velocity = initial_velocity
	angular_velocity = Vector3.ZERO
	global_transform = value
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	state = State.AIR
	contact = SkiContactSolver.new()
	edge_amount = 0.0
	pressure_amount = 0.0
	lateral_slip = 0.0
	carve_force = 0.0
	steering_input_raw = 0.0
	steering_input = 0.0
	brake_amount = 0.0
	effective_steer_rate = 0.0
	available_grip = 0.0
	centripetal_demand = 0.0
	current_carve_ratio = 1.0
	skid_amount = 0.0
	heading_travel_angle_degrees = 0.0
	slope_angle_degrees = 0.0
	coyote_remaining = 0.0
	jump_charge = 0.0
	tuck_amount = 0.0
	braking = false
	air_time = 0.0
	rail_balance_input = 0.0
	rail_balance = 0.0
	rail_offset = 0.0
	rail_direction = 1.0
	rail_speed = 0.0
	rail_prev_tangent = Vector3.ZERO
	rail_capture_from_position = Vector3.ZERO
	rail_capture_blend_remaining = 0.0
	rail_pose = 0
	bail_time = 0.0
	bail_recovering = false
	grab_amount = 0.0
	grab_tweak = Vector2.ZERO
	grab_release_time = 0.0
	predicted_landing_time = -1.0
	landing_feedback_armed = false
	air_deliberate = false
	wall_pin_time = 0.0
	last_collision_diagnostics.clear()
	last_collision_colliders.clear()
	last_speed_discontinuity = {}
	trick_sample.reset()
	trick_command.reset()
	trick.reset()
	flick.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	gesture_strength = 0.0
	if scoring != null:
		scoring.reset_run()
	if spray != null:
		spray.emitting = false
	if animation_controller != null:
		animation_controller.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
	state_changed.emit("Air")

func _record_motion_diagnostics(velocity_before_motion: Vector3) -> void:
	var speed_before := velocity_before_motion.length()
	var speed_after := velocity.length()
	var speed_loss := speed_before - speed_after
	var discontinuity := speed_loss >= maxf(3.0, speed_before * 0.35)
	var collision_count := get_slide_collision_count()
	for index: int in range(collision_count):
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		last_collision_colliders.append(collider.name if collider is Node else "<unnamed>")
		var collision_speed_change := absf(speed_after - speed_before)
		if collision_speed_change < 2.0 and not discontinuity:
			continue
		last_collision_diagnostics.append({
				"collider": collider.name if collider is Node else "<unnamed>",
				"normal": collision.get_normal(),
				"position": collision.get_position(),
				"velocity_before": velocity_before_motion,
				"velocity_after": velocity,
				"speed_before": speed_before,
				"speed_after": speed_after,
				"grounded": contact.grounded,
			})
	if discontinuity:
		last_speed_discontinuity = {
			"diagnostic": "SPEED_DISCONTINUITY",
			"velocity_before": velocity_before_motion,
			"velocity_after": velocity,
			"speed_before": speed_before,
			"speed_after": speed_after,
			"speed_loss": speed_loss,
			"grounded": contact.grounded,
			"collisions": collision_count,
		}

func telemetry() -> Dictionary:
	return {
		"speed_mps": velocity.length(),
		"speed_kph": velocity.length() * 3.6,
		"state": State.keys()[state],
		"grounded": contact.grounded,
		"contact_confidence": contact.confidence,
		"surface_kind": contact.surface_kind,
		"surface": _surface_name(),
		"surface_normal": contact.average_normal,
		"edge": edge_amount,
		"steering_raw": steering_input_raw,
		"steering": steering_input,
		"effective_steer_rate": effective_steer_rate,
		"brake_amount": brake_amount,
		"pressure": pressure_amount,
		"lateral_slip": lateral_slip,
		"skid_amount": skid_amount,
		"carve_ratio": current_carve_ratio,
		"carve_force": carve_force,
		"available_grip": available_grip,
		"centripetal_demand": centripetal_demand,
		"heading_travel_angle_degrees": heading_travel_angle_degrees,
		"slope_angle_degrees": slope_angle_degrees,
		"angular_velocity": angular_velocity,
		"rail": active_rail.name if active_rail != null else "—",
		"rail_balance": rail_balance,
		"predicted_landing_time": predicted_landing_time,
		"landing_feedback_armed": landing_feedback_armed,
		"collision_count": get_slide_collision_count(),
		"collision_colliders": last_collision_colliders,
		"collision_diagnostics": last_collision_diagnostics,
		"speed_discontinuity": last_speed_discontinuity,
		"upright_dot": global_basis.y.normalized().dot(contact.average_normal.normalized()),
		"line_link": scoring.link_remaining > 0.0,
		"scoring": scoring.snapshot(),
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
	# Seat the capsule so its resting contact puts the body origin at the seat
	# height above the snow (skis kissing the surface) instead of sinking below it.
	shape.position.y = 0.67
	add_child(shape)
	animation_controller = SkierAnimationController.new()
	animation_controller.name = "SkierAnimationController"
	visual_root = animation_controller
	add_child(animation_controller)

func _build_spray() -> void:
	spray = GPUParticles3D.new()
	spray.amount = 140
	spray.lifetime = 0.85
	spray.explosiveness = 0.05
	spray.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 8, 10))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 0.85, 0.55)
	process_material.spread = 48.0
	process_material.initial_velocity_min = 1.6
	process_material.initial_velocity_max = 6.2
	process_material.gravity = Vector3(0.0, -5.5, 0.0)
	process_material.damping_min = 0.4
	process_material.damping_max = 1.2
	process_material.scale_min = 0.035
	process_material.scale_max = 0.11
	process_material.color = Color(0.93, 0.97, 1.0, 0.82)
	spray.process_material = process_material
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.07, 0.07)
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = Color(0.95, 0.98, 1.0, 0.7)
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.emission_enabled = true
	particle_material.emission = Color(0.85, 0.93, 1.0)
	particle_material.emission_energy_multiplier = 0.35
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
	trick_sample.left_stick = InputManager.vector(&"steer_left", &"steer_right", &"steer_forward", &"steer_back")
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
	predicted_landing_time = _predict_landing_time()
	var predicted_landing := predicted_landing_time
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
	animation_frame.compression = clampf(jump_charge / maxf(profile.maximum_jump_charge, 0.001), 0.0, 1.0)
	animation_frame.contact_confidence = contact.confidence
	animation_frame.ground_normal = contact.average_normal
	animation_frame.angular_velocity = angular_velocity
	animation_frame.vertical_velocity = velocity.y
	animation_frame.air_time = air_time
	animation_frame.predicted_landing_time = predicted_landing
	animation_frame.grab_pose = trick.grab_pose
	animation_frame.switch_stance = velocity.dot(-global_basis.z) < 0.0
	animation_frame.rail_speed = absf(rail_speed) if state == State.GRIND else 0.0
	animation_frame.rail_balance = rail_balance if state == State.GRIND else 0.0
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
	if state != State.AIR:
		return -1.0
	var step := clampf(profile.landing_prediction_step, 0.025, 0.15)
	var elapsed := 0.0
	var position := global_position + Vector3.UP * 0.2
	var predicted_velocity := velocity
	var space := get_world_3d().direct_space_state
	while elapsed < profile.landing_prediction_seconds:
		var next_velocity := predicted_velocity + Vector3.DOWN * profile.air_gravity * step
		var next_position := position + (predicted_velocity + next_velocity) * 0.5 * step
		var query := PhysicsRayQueryParameters3D.create(position, next_position, 1)
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			return elapsed + step
		position = next_position
		predicted_velocity = next_velocity
		elapsed += step
	return -1.0

func _surface_drag_multiplier() -> float:
	match contact.surface_kind:
		1: return profile.packed_drag_multiplier
		2: return profile.groomed_drag_multiplier
	return profile.powder_drag_multiplier

func _surface_grip_multiplier() -> float:
	match contact.surface_kind:
		1: return profile.packed_grip_multiplier
		2: return profile.groomed_grip_multiplier
	return profile.powder_grip_multiplier

func _surface_name() -> String:
	match contact.surface_kind:
		1: return "Packed"
		2: return "Groomed"
	return "Powder"

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
