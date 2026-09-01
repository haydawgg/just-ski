class_name SkierController
extends CharacterBody3D

signal respawn_applied(transform: Transform3D)

const SkierVisualScene := preload("res://player/animation/skier_visual.tscn")
const ParkLayout := preload("res://world/park_features/park_layout.gd")
const GroundMotionSolverModule := preload("res://player/motion/ground_motion_solver.gd")
const AirMotionSolverModule := preload("res://player/motion/air_motion_solver.gd")
const RailMotionSolverModule := preload("res://player/motion/rail_motion_solver.gd")
const LandingTransitionModule := preload("res://player/motion/landing_transition.gd")
const CollisionCrashEvaluatorModule := preload("res://player/motion/collision_crash_evaluator.gd")

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
var rail_entry_severity := 0.0
var bail_time := 0.0
var bail_recovering := false
var debug_enabled := false
var trick: TrickController
var scoring: RunScoring
var snow_vfx: SkiSnowVFX
var visual_root: Node3D
var animation_controller: SkierAnimationController
var animation_frame := SkierAnimationFrame.new()
var debug_mesh: ImmediateMesh
var flick: FlickTrickInterpreter
var trick_sample := TrickInputSample.new()
var trick_command: TrickCommand
var trick_rotation_state := TrickRotationState.new()
var active_trick_kind := TrickCommand.Kind.NONE
var trick_phase := TrickCommand.PresentationPhase.NEUTRAL
var gesture_strength := 0.0
var grab_amount := 0.0
var grab_tweak := Vector2.ZERO
var grab_release_time := 0.0
var rail_pose := 0
var predicted_landing_time := -1.0
var predicted_landing_normal := Vector3.UP
var predicted_landing_point := Vector3.ZERO
var predicted_landing_valid := false
var landing_feedback_armed := false
var landing_context := {}
var landing_control_multiplier := 1.0
var landing_control_recovery_rate := 0.0
var landing_orientation_remaining := 0.0
var landing_orientation_duration := 0.0
# Airborne angular velocity is local-space. The landing residual is world-space
# so its yaw/tilt split remains relative to the receiving surface normal.
var landing_residual_angular_velocity := Vector3.ZERO
var air_deliberate := false
var air_takeoff_type := SkierAnimationFrame.TakeoffType.NONE
var air_takeoff_charge := 0.0
var air_takeoff_upward_speed := 0.0
var air_reference_up := Vector3.UP
var wall_pin_time := 0.0
var last_collision_diagnostics: Array[Dictionary] = []
var last_collision_colliders: Array[String] = []
var last_speed_discontinuity: Dictionary = {}
var crash_context := CrashContext.new()
var recent_rail_detach_time := 0.0
var recent_rail_detach_balance := 0.0
var respawn_count := 0
var recovery_frozen := false
var contact_shadow: MeshInstance3D
var contact_shadow_material: ShaderMaterial
var _ground_motion_solver := GroundMotionSolverModule.new()
var _air_motion_solver := AirMotionSolverModule.new()
var _rail_motion_solver := RailMotionSolverModule.new()
var _landing_transition := LandingTransitionModule.new()
var _collision_crash_evaluator := CollisionCrashEvaluatorModule.new()

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.42
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_build_body()
	_build_snow_vfx()
	_build_contact_shadow()
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

func _exit_tree() -> void:
	# SessionManager is an autoload and outlives test/run skier instances. Remove
	# the bound callback explicitly so deleted skiers cannot be retained by the
	# singleton or receive a later respawn request.
	if SessionManager.respawn_requested.is_connected(respawn_at):
		SessionManager.respawn_requested.disconnect(respawn_at)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		debug_enabled = not debug_enabled
		if recovery_frozen:
			return
	if recovery_frozen:
		return
	if event.is_action_pressed("respawn"):
		SessionManager.request_respawn()
	if event.is_action_pressed("set_marker") and state == State.GROUND and contact.grounded:
		var safe_transform := global_transform
		safe_transform.origin += contact.average_normal * 0.5
		SessionManager.set_marker(safe_transform)

func _physics_process(delta: float) -> void:
	if recovery_frozen:
		# Recovery freezes gameplay motion, not the observers that drive HUD,
		# combo expiry, and surface audio. Keep those channels ticking so the
		# recovery overlay cannot leave stale telemetry or a held sound loop.
		if scoring != null:
			scoring.step(delta, velocity.length())
		AudioManager.update_surface_audio(velocity.length(), skid_amount, state == State.GRIND, contact.surface_kind, state == State.AIR)
		telemetry_updated.emit(telemetry())
		return
	var velocity_before_motion := velocity
	last_collision_diagnostics.clear()
	last_collision_colliders.clear()
	last_speed_discontinuity = {}
	contact.sample(
		self,
		profile.ground_probe_distance,
		profile.ground_probe_reach,
		profile.contact_probe_offsets(),
		profile.ground_probe_origin_height
	)
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
		_evaluate_feature_crash_after_motion()
		if state == State.GROUND and contact.grounded:
			_suppress_into_slope_bounce()
			_update_wall_pin(delta)
	scoring.step(delta, velocity.length())
	_update_animation(delta)
	snow_vfx.update_from_existing_contact(delta)
	_update_contact_shadow(delta)
	_update_debug()
	AudioManager.update_surface_audio(velocity.length(), skid_amount, state == State.GRIND, contact.surface_kind, state == State.AIR)
	telemetry_updated.emit(telemetry())

func _update_ground(delta: float) -> void:
	var ground_contact := _ground_motion_solver.resolve_contact(contact.grounded, coyote_remaining, delta, profile.coyote_time)
	coyote_remaining = ground_contact.coyote_remaining
	if ground_contact.should_enter_air:
		_enter_air()
		return
	_update_landing_control_recovery(delta)
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
	# Probe rays start at the profile-defined height above the body origin.
	if contact.grounded and contact.hit_points.size() > 0:
		var seat_distance := profile.ground_probe_origin_height + profile.ground_attach_height
		var attach_gap := contact.average_distance - seat_distance
		if attach_gap > 0.0:
			var probe_origin := global_position + normal * profile.ground_probe_origin_height
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
	# Hard impacts briefly soften the complete turn response without locking the
	# player out. Braking keeps full authority so recovery remains accessible.
	effective_steer_rate *= lerpf(landing_control_multiplier, 1.0, brake_amount)
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
	turned_forward = _ground_motion_solver.constrain_heading_to_travel(
		turned_forward,
		velocity,
		normal,
		speed_ratio,
		delta,
		profile.low_speed_heading_travel_limit_degrees,
		profile.high_speed_heading_travel_limit_degrees,
		profile.heading_travel_limit_response
	)
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
		aligned_up = surface_up
	var ground_target_basis := Basis.looking_at(
		turned_forward.normalized(),
		aligned_up
	).orthonormalized()
	global_basis = _apply_ground_orientation(ground_target_basis, surface_up, delta)

	if trick_command.phase == TrickCommand.PresentationPhase.SETUP:
		jump_charge = maxf(jump_charge, trick_command.gesture_strength * profile.maximum_jump_charge)
	if trick_command.pop_strength > 0.0:
		_pop(normal, trick_command.pop_strength, trick_command.rotation_impulse, trick_command.kind, delta)
	elif Input.is_action_pressed("jump"):
		jump_charge = minf(jump_charge + delta, profile.maximum_jump_charge)
	if trick_command.pop_strength <= 0.0 and Input.is_action_just_released("jump"):
		_pop(normal, -1.0, Vector3.ZERO, TrickCommand.Kind.POP, delta)
	elif Input.is_action_just_pressed("jump") and last_physics_delta > 0.0:
		jump_charge = maxf(jump_charge, 0.06)

	AudioManager.skid_feedback(skid_amount)

func _apply_ground_orientation(target_basis: Basis, surface_normal: Vector3, delta: float) -> Basis:
	var current := global_basis.orthonormalized()
	var target := target_basis.orthonormalized()
	if landing_orientation_duration <= 0.0:
		landing_residual_angular_velocity = Vector3.ZERO
		return target
	var dt := maxf(delta, 0.0)
	if dt <= 0.0:
		return current
	landing_residual_angular_velocity *= exp(-profile.landing_residual_angular_damping * dt)
	var remaining_angle := deg_to_rad(maxf(profile.landing_orientation_max_rate_degrees, 0.0)) * dt
	if remaining_angle <= 0.0:
		return current

	# Apply residual rotation in the current body frame, but account for it in
	# the same angular budget as target convergence so the root never exceeds the
	# configured per-frame rate ceiling.
	var residual_speed_squared := landing_residual_angular_velocity.length_squared()
	if residual_speed_squared > 0.000001:
		var local_residual := current.inverse() * landing_residual_angular_velocity
		var residual_basis := AirRotationIntegrator.integrate_basis(current, local_residual, dt)
		var current_quaternion := current.get_rotation_quaternion()
		var residual_quaternion := residual_basis.get_rotation_quaternion()
		var residual_step := current_quaternion.angle_to(residual_quaternion)
		if residual_step > remaining_angle and residual_step > 0.000001:
			current = Basis(current_quaternion.slerp(residual_quaternion, remaining_angle / residual_step)).orthonormalized()
			remaining_angle = 0.0
		else:
			current = residual_basis
			remaining_angle -= residual_step

	var current_quaternion := current.get_rotation_quaternion()
	var target_quaternion := target.get_rotation_quaternion()
	var error := current_quaternion.angle_to(target_quaternion)
	if remaining_angle > 0.0 and error > 0.000001:
		var target_step := minf(error, remaining_angle)
		current = Basis(current_quaternion.slerp(target_quaternion, target_step / error)).orthonormalized()

	landing_orientation_remaining = maxf(landing_orientation_remaining - dt, 0.0)
	var final_error := current.get_rotation_quaternion().angle_to(target_quaternion)
	if final_error <= deg_to_rad(1.0):
		landing_orientation_remaining = 0.0
		landing_orientation_duration = 0.0
		landing_residual_angular_velocity = Vector3.ZERO
	elif landing_orientation_remaining <= 0.0:
		# The configured duration is an envelope, not permission to snap. Keep
		# the continuity seam active until the remaining error is rate-safe.
		landing_orientation_duration = maxf(landing_orientation_duration, dt)
	return current

func _begin_landing_orientation_settle(severity: float) -> void:
	var bounded_severity := clampf(severity, 0.0, 1.0)
	var normal := contact.average_normal.normalized() if contact.average_normal.length_squared() > 0.0001 else Vector3.UP
	var world_angular_velocity := AirRotationIntegrator.local_to_world_angular_velocity(global_basis, angular_velocity)
	var yaw_component := normal * world_angular_velocity.dot(normal)
	var tilt_component := world_angular_velocity - yaw_component
	landing_residual_angular_velocity = (
		yaw_component * profile.landing_residual_yaw_transfer
		+ tilt_component * profile.landing_residual_tilt_transfer
	)
	landing_orientation_duration = maxf(lerpf(
		profile.landing_orientation_settle_time_soft,
		profile.landing_orientation_settle_time_hard,
		bounded_severity
	), 0.0)
	landing_orientation_remaining = landing_orientation_duration

func _clear_landing_orientation_settle() -> void:
	landing_orientation_remaining = 0.0
	landing_orientation_duration = 0.0
	landing_residual_angular_velocity = Vector3.ZERO

func _constrain_heading_to_travel(candidate: Vector3, normal: Vector3, speed_ratio: float, delta: float) -> Vector3:
	return _ground_motion_solver.constrain_heading_to_travel(
		candidate,
		velocity,
		normal,
		speed_ratio,
		delta,
		profile.low_speed_heading_travel_limit_degrees,
		profile.high_speed_heading_travel_limit_degrees,
		profile.heading_travel_limit_response
	)

func _update_air(delta: float) -> void:
	air_time += delta
	recent_rail_detach_time = maxf(0.0, recent_rail_detach_time - delta)
	braking = false
	brake_amount = 0.0
	skid_amount = 0.0
	tuck_amount = 0.0
	var air_motion := _air_motion_solver.step_gravity(velocity, delta, profile.air_gravity, profile.air_terminal_speed)
	velocity = air_motion.velocity
	if trick_command.committed:
		angular_velocity += trick_command.rotation_impulse
	if trick_rotation_state.active and trick_command.takeoff_release_impulse.length_squared() > 0.0000001:
		trick_rotation_state.record_takeoff_release(trick_command.takeoff_release_impulse, delta)
	var predicted := _predict_landing_time()
	if trick_rotation_state.active:
		var assist_availability := _air_motion_solver.landing_assist_availability(predicted, profile.air_landing_window)
		var trim_acceleration := Vector3(
			-trick_sample.left_stick.y * profile.air_flip_trim_acceleration,
			-trick_sample.left_stick.x * flick_profile.air_yaw_trim_acceleration,
			0.0
		) * assist_availability
		angular_velocity += trick_rotation_state.consume_assist_acceleration(trim_acceleration, delta)
	angular_velocity = angular_velocity.limit_length(profile.maximum_angular_speed)
	var rotation_compactness := _air_rotation_compactness(predicted)
	if trick_rotation_state.active:
		angular_velocity = trick_rotation_state.apply_compactness(
			angular_velocity,
			rotation_compactness,
			delta,
			profile.air_open_inertia_scale,
			profile.air_compact_inertia_scale,
			profile.air_inertia_response_rate
		)
	var body_damping_multiplier := lerpf(
		profile.air_open_damping_multiplier,
		profile.air_compact_damping_multiplier,
		rotation_compactness
	) if trick_rotation_state.active else 1.0
	var damping := profile.air_angular_damping * body_damping_multiplier
	var landing_assist := float(GameSettings.active.get("landing_assist", 0.35))
	if predicted >= 0.0 and predicted < profile.air_landing_window:
		var landing_proximity := 1.0 - predicted / maxf(profile.air_landing_window, 0.01)
		var assist_weight := landing_proximity * landing_assist * profile.air_landing_assist_damping_weight
		damping = lerpf(damping, profile.air_landing_damping, assist_weight)
	angular_velocity *= exp(-damping * delta)
	if trick_rotation_state.active:
		var world_angular_velocity := AirRotationIntegrator.local_to_world_angular_velocity(global_basis, angular_velocity)
		trick_rotation_state.integrate_world_angular_velocity(world_angular_velocity, delta)
	global_basis = AirRotationIntegrator.integrate_basis(global_basis, angular_velocity, delta)
	if trick_rotation_state.active:
		trick_rotation_state.record_world_basis(global_basis)
		trick.update_air_authoritative(
			angular_velocity,
			delta,
			trick_command,
			trick_rotation_state.accumulated_rotation_vector()
		)
	else:
		trick.update_air(angular_velocity, delta, trick_command)
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

func _air_rotation_compactness(predicted_landing: float) -> float:
	if not trick_rotation_state.active:
		return 0.5
	var target := 0.5
	if grab_amount > 0.05:
		target = 0.88
	else:
		match trick_command.style_pose:
			TrickController.StylePose.SPREAD_EAGLE, TrickController.StylePose.DAFFY:
				target = 0.08
			TrickController.StylePose.SHIFTY_LEFT, TrickController.StylePose.SHIFTY_RIGHT:
				target = 0.38
			_:
				var projection := trick_rotation_state.control_projection(
					trick_sample.right_stick,
					flick_profile.center_reset_threshold
				)
				if projection > flick_profile.continuous_axis_deadzone:
					target = lerpf(0.5, 0.84, projection)
				elif projection < -flick_profile.continuous_axis_deadzone:
					target = lerpf(0.5, 0.12, -projection)
	if predicted_landing >= 0.0 and predicted_landing < profile.air_landing_window:
		var landing_open := 1.0 - predicted_landing / maxf(profile.air_landing_window, 0.01)
		target = lerpf(target, 0.05, smoothstep(0.0, 1.0, landing_open))
	return clampf(target, 0.0, 1.0)

func _update_grind(delta: float) -> void:
	if active_rail == null:
		_enter_air()
		return
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction
	rail_balance_input = trick_sample.left_stick.x
	brake_amount = 0.0
	skid_amount = 0.0
	var slope_acceleration := Vector3.DOWN.dot(tangent) * profile.gravity
	var rail_motion := _rail_motion_solver.advance(
		rail_speed,
		rail_offset,
		rail_direction,
		active_rail.path_length,
		slope_acceleration,
		profile.rail_friction + active_rail.base_friction,
		delta
	)
	rail_speed = rail_motion.speed
	rail_offset = rail_motion.offset
	if rail_motion.reached_end:
		_exit_rail(false)
		return
	# Balance: left stick counters drift; kinks and boardslides add instability.
	var kink := 0.0
	if rail_prev_tangent.length_squared() > 0.01:
		kink = 1.0 - clampf(rail_prev_tangent.normalized().dot(tangent.normalized()), 0.0, 1.0)
	rail_prev_tangent = tangent
	var boardslide_factor := 1.0 + absf(float(rail_pose)) * profile.rail_boardslide_instability
	var drift := (profile.rail_balance_drift + kink * profile.rail_kink_instability) * boardslide_factor
	rail_balance = _rail_motion_solver.update_balance(
		rail_balance,
		rail_balance_input,
		drift,
		active_rail.drift_bias,
		profile.rail_balance_input_gain,
		delta
	)
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
	crash_context.elapsed += delta
	bail_time = maxf(0.0, profile.crash_max_duration - crash_context.elapsed)
	velocity += Vector3.DOWN * profile.air_gravity * delta
	if contact.grounded:
		velocity = velocity.slide(contact.average_normal)
		var ground_damping := profile.bail_ground_damping
		var angular_damping := profile.crash_ground_angular_damping
		if crash_context.stage == CrashContext.Stage.FALL:
			ground_damping *= 0.55
			angular_damping *= 0.6
		elif crash_context.stage == CrashContext.Stage.REST:
			ground_damping *= 0.38
			angular_damping *= 0.45
		velocity *= exp(-ground_damping * delta)
		angular_velocity *= exp(-angular_damping * delta)
		# Rest stage retains a faint velocity-driven secondary wobble instead of freezing.
		if crash_context.stage == CrashContext.Stage.REST and velocity.length() > 0.15:
			var wobble_axis := Vector3.UP.cross(velocity.normalized())
			if wobble_axis.length_squared() > 0.001:
				angular_velocity += wobble_axis.normalized() * 0.08 * clampf(velocity.length() / 5.0, 0.0, 1.0) * delta
		var aligned_up := global_basis.y.lerp(contact.average_normal, 1.0 - exp(-profile.bail_ground_align_rate * delta)).normalized()
		var forward := (-global_basis.z).slide(contact.average_normal)
		if forward.length_squared() < 0.0001:
			forward = contact.downhill()
		if forward.length_squared() > 0.0001:
			global_basis = Basis.looking_at(forward.normalized(), aligned_up)
	else:
		angular_velocity *= exp(-profile.crash_air_angular_damping * delta)
		rotate_object_local(Vector3.RIGHT, angular_velocity.x * delta)
		rotate_object_local(Vector3.UP, angular_velocity.y * delta)
		rotate_object_local(Vector3.BACK, angular_velocity.z * delta)
		global_basis = global_basis.orthonormalized()
		# Prevent sustained vertical post where skis appear as a pole through the character.
		var up_dot := global_basis.y.dot(Vector3.UP)
		if up_dot < 0.45:
			var forward := -global_basis.z
			if forward.length_squared() < 0.001:
				forward = Vector3.FORWARD
			var target_basis := Basis.looking_at(forward.normalized(), Vector3.UP)
			global_basis = global_basis.slerp(target_basis, 0.68)
			global_basis = global_basis.orthonormalized()
			# Strongly damp angular velocity when correcting from extreme inversion.
			angular_velocity *= 0.62
			# Add upright torque to prevent lingering vertical.
			var upright_torque := Vector3.UP.cross(global_basis.y).normalized() * 4.5 * (0.45 - up_dot)
			angular_velocity += upright_torque * delta
			# Clamp angular velocity to prevent re-tumbling into vertical.
			angular_velocity = angular_velocity.limit_length(3.5)
	crash_context.current_velocity = velocity
	crash_context.angular_speed = angular_velocity.length()
	_update_crash_stage_and_rest(delta)

func _pop(
	normal: Vector3,
	requested_strength: float = -1.0,
	rotation_impulse: Vector3 = Vector3.ZERO,
	takeoff_kind: int = TrickCommand.Kind.POP,
	delta: float = 0.0
) -> void:
	var normalized_charge := clampf(jump_charge / maxf(profile.maximum_jump_charge, 0.001), 0.0, 1.0)
	var strength := requested_strength if requested_strength >= 0.0 else lerpf(profile.minimum_pop_strength, 1.0, normalized_charge)
	velocity += normal * profile.pop_impulse * strength
	AudioManager.pop_feedback(strength)
	animation_controller.trigger(SkierAnimationController.AnimationEvent.POP, strength)
	jump_charge = 0.0
	_enter_air(takeoff_kind, normalized_charge, normal)
	air_deliberate = true
	if trick_command.takeoff_rotation_committed and trick_command.takeoff_rotation_impulse.length_squared() > 0.000001:
		trick_rotation_state.begin(
			takeoff_kind,
			global_basis,
			trick_command.takeoff_rotation_impulse,
			flick_profile.takeoff_release_duration,
			flick_profile.air_assist_budget
		)
		trick_rotation_state.record_takeoff_release(trick_command.takeoff_release_impulse, delta)
	angular_velocity = (angular_velocity + rotation_impulse).limit_length(profile.maximum_angular_speed)

func _enter_air(takeoff_kind: int = TrickCommand.Kind.NONE, normalized_charge: float = 0.0, takeoff_normal: Vector3 = Vector3.ZERO) -> void:
	if state == State.AIR:
		return
	air_reference_up = takeoff_normal.normalized() if takeoff_normal.length_squared() > 0.01 else contact.last_normal.normalized()
	if air_reference_up.length_squared() < 0.01:
		air_reference_up = Vector3.UP
	air_takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP if takeoff_kind != TrickCommand.Kind.NONE else SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF
	air_takeoff_charge = clampf(normalized_charge, 0.0, 1.0)
	air_takeoff_upward_speed = maxf(0.0, velocity.dot(air_reference_up))
	state = State.AIR
	air_deliberate = false
	landing_feedback_armed = true
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_clear_landing_orientation_settle()
	angular_velocity = Vector3.ZERO
	trick_rotation_state.reset()
	air_time = 0.0
	active_trick_kind = takeoff_kind
	trick.begin_air(
		velocity.dot(-global_basis.z) < 0.0,
		takeoff_kind,
		takeoff_kind != TrickCommand.Kind.NONE,
		trick_command.rotation_axis_local
	)
	state_changed.emit("Air")

func _handle_landing() -> void:
	var transition := _landing_transition.evaluate(global_basis.y, -global_basis.z, contact.average_normal, velocity, angular_velocity, profile)
	var result: Dictionary = transition.data
	_apply_trick_rotation_to_landing(result)
	_landing_transition.apply_assist(transition, float(GameSettings.active.get("landing_assist", 0.35)), profile)
	var should_present_landing := landing_feedback_armed
	landing_feedback_armed = false
	_capture_landing_context(result, true)
	if int(result.outcome) == LandingSolver.Outcome.BAIL:
		enter_crash(_landing_crash_context(result))
		return
	if should_present_landing:
		AudioManager.landing_feedback(float(result.score), float(result.impact))
		landed.emit(result)
	_begin_landing_control_recovery(float(result.impact_severity))
	var landing_event := SkierAnimationController.AnimationEvent.LAND_CLEAN
	if int(result.outcome) == LandingSolver.Outcome.SKETCHY:
		landing_event = SkierAnimationController.AnimationEvent.LAND_SKETCHY
	elif int(result.outcome) == LandingSolver.Outcome.HARD:
		landing_event = SkierAnimationController.AnimationEvent.LAND_HARD
	animation_controller.trigger(landing_event, float(result.impact_severity), signf(float(result.lateral_velocity)))
	var quality := float(result.score)
	velocity = velocity.slide(contact.average_normal)
	if int(result.outcome) == LandingSolver.Outcome.SKETCHY:
		velocity *= profile.sketchy_landing_speed_retain
	elif int(result.outcome) == LandingSolver.Outcome.HARD:
		velocity *= profile.hard_landing_speed_retain
	_begin_landing_orientation_settle(float(result.impact_severity))
	angular_velocity = Vector3.ZERO
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	state = State.GROUND
	if trick.had_trick_intent:
		scoring.begin_feature("jump")
	trick.land(quality, velocity.dot(-global_basis.z) < 0.0, int(result.outcome), 0, true)
	trick_rotation_state.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	rail_pose = 0
	state_changed.emit("Ground")

func _begin_landing_control_recovery(severity: float) -> void:
	var bounded_severity := clampf(severity, 0.0, 1.0)
	var penalty := profile.landing_control_penalty_max * bounded_severity
	landing_control_multiplier = minf(landing_control_multiplier, 1.0 - penalty)
	var recovery_time := lerpf(
		profile.landing_control_recovery_time_soft,
		profile.landing_control_recovery_time_hard,
		bounded_severity
	)
	landing_control_recovery_rate = (1.0 - landing_control_multiplier) / maxf(recovery_time, 0.01)

func _update_landing_control_recovery(delta: float) -> void:
	landing_control_multiplier = move_toward(landing_control_multiplier, 1.0, landing_control_recovery_rate * delta)
	if landing_control_multiplier >= 0.999:
		landing_control_multiplier = 1.0
		landing_control_recovery_rate = 0.0

func _capture_landing_context(result: Dictionary, deliberate: bool) -> void:
	var rotation_error := 0.0
	var rotation_accumulated := Vector3.ZERO
	var rotation_residual := Vector3.ZERO
	if trick != null and trick.had_trick_intent:
		rotation_accumulated = trick.accumulated_rotation
		rotation_residual = trick.rotation_residual_vector()
		rotation_error = rotation_residual.y / PI
	var air_scale := 1.0 if deliberate else clampf(air_time / maxf(animation_controller.profile.landing_hop_air_time_reference, 0.01), animation_controller.profile.landing_min_air_time_scale, 1.0)
	landing_context = {
		"impact_speed": float(result.impact),
		"impact_severity": float(result.impact_severity) * air_scale,
		"balance_error": float(result.balance_error) * air_scale,
		"ski_alignment_error": float(result.ski_alignment_error),
		"body_roll_error": float(result.body_roll_error),
		"body_pitch_error": float(result.body_pitch_error),
		"rotation_error": rotation_error,
		"rotation_accumulated": rotation_accumulated,
		"rotation_residual": rotation_residual,
		"lateral_velocity": float(result.lateral_velocity),
		"forward_velocity": float(result.forward_velocity),
		"air_time": air_time,
		"surface_normal": contact.average_normal,
		"outcome": int(result.outcome),
		"active": true,
		"deliberate": deliberate,
	}

func _apply_trick_rotation_to_landing(result: Dictionary) -> void:
	if trick == null or not trick.had_trick_intent or trick.rotation_target_degrees() <= 0:
		return
	var residual_degrees := trick.rotation_residual_degrees()
	var rotation_quality := trick.rotation_quality_factor()
	var orientation_error_degrees := rad_to_deg(trick_rotation_state.orientation_error_radians()) if trick_rotation_state.active else 0.0
	result.score = clampf(float(result.score) * rotation_quality, 0.0, 1.0)
	result.balance_error = maxf(
		float(result.balance_error),
		maxf(
			clampf(absf(residual_degrees) / 90.0, 0.0, 1.0),
			clampf(orientation_error_degrees / 90.0, 0.0, 1.0)
		)
	)
	result["rotation_residual_degrees"] = residual_degrees
	result["rotation_quality"] = rotation_quality
	result["rotation_orientation_error_degrees"] = orientation_error_degrees

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
	var result: Dictionary = _landing_transition.evaluate(global_basis.y, -global_basis.z, contact.average_normal, velocity, angular_velocity, profile).data
	_capture_landing_context(result, false)
	animation_controller.trigger(
		SkierAnimationController.AnimationEvent.LAND_CLEAN,
		float(landing_context.get("impact_severity", 0.12)),
		signf(float(result.lateral_velocity))
	)
	velocity = velocity.slide(contact.average_normal)
	_clear_landing_orientation_settle()
	angular_velocity = Vector3.ZERO
	var projected_forward := (-global_basis.z).slide(contact.average_normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = contact.downhill()
	if projected_forward.length_squared() < 0.0001:
		projected_forward = Vector3.FORWARD
	global_basis = Basis.looking_at(projected_forward.normalized(), contact.average_normal.normalized()).orthonormalized()
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	state = State.GROUND
	trick_rotation_state.reset()
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
		# Entry severity scales the sharper, smaller absorption pose from
		# actual capture-moment physics: how hard the skier drops into the
		# feature, how misaligned the approach is, and current body tilt.
		var approach_alignment := absf(velocity.normalized().dot((best.tangent as Vector3).normalized())) if velocity.length_squared() > 0.0001 else 1.0
		var vertical_impact := maxf(0.0, -velocity.dot(Vector3.UP))
		var body_alignment_error := 1.0 - clampf(global_basis.y.normalized().dot(Vector3.UP), 0.0, 1.0)
		rail_entry_severity = clampf(
			vertical_impact / maxf(profile.rail_entry_severity_speed_reference, 0.01) * 0.55
			+ (1.0 - approach_alignment) * 0.25
			+ body_alignment_error * 0.2,
			0.0,
			1.0
		)
		state = State.GRIND
		rail_pose = 0
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_ENTER, rail_entry_severity, lateral_bias)
		state_changed.emit("Grind")

func _rail_distance_to_end() -> float:
	if active_rail == null:
		return 0.0
	return active_rail.path_length - rail_offset if rail_direction > 0.0 else rail_offset

func _scan_rail_approach() -> float:
	# Read-only proximity/heading score used only for subtle pre-capture
	# anticipation. Never attaches; capture_candidate remains authoritative.
	if state == State.GRIND or velocity.length() < 1.0:
		return 0.0
	var best_score := 0.0
	for node: Node in get_tree().get_nodes_in_group("grind_rails"):
		var rail := node as GrindRail3D
		var preview := rail.approach_preview(global_position, velocity, profile.rail_preview_radius)
		if bool(preview.get("valid", false)):
			var score := 1.0 - clampf(float(preview.distance) / maxf(profile.rail_preview_radius, 0.01), 0.0, 1.0)
			best_score = maxf(best_score, score)
	return best_score

func _exit_rail(pop_off: bool) -> void:
	var tangent := active_rail.tangent_at(rail_offset) * rail_direction if active_rail != null else -global_basis.z
	velocity = tangent * rail_speed
	if pop_off:
		velocity += Vector3.UP * profile.pop_impulse * profile.rail_pop_strength
	animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, clampf(absf(rail_speed) / 20.0, 0.25, 1.0), rail_direction)
	if trick.grind_seconds > 0.05:
		scoring.begin_feature("rail")
		trick.land(0.85, false, LandingSolver.Outcome.CLEAN)
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
	var failed_balance := rail_balance
	velocity = (
		tangent * rail_speed * profile.rail_slip_speed_retain
		+ sideways * signf(rail_balance) * profile.rail_slip_lateral_speed
		+ Vector3.UP * profile.rail_slip_upward_speed
	)
	animation_controller.trigger(SkierAnimationController.AnimationEvent.GRIND_EXIT, 0.45, signf(rail_balance))
	active_rail = null
	rail_balance = 0.0
	rail_capture_blend_remaining = 0.0
	recent_rail_detach_time = 1.0
	recent_rail_detach_balance = failed_balance
	scoring.reset_link()
	_enter_air()

func enter_crash(context: CrashContext) -> bool:
	if state == State.BAIL or context == null or not context.active:
		return false
	_clear_landing_orientation_settle()
	crash_context = context
	state = State.BAIL
	bail_time = profile.crash_max_duration
	bail_recovering = true
	landing_context = {}
	landing_control_multiplier = 1.0
	landing_control_recovery_rate = 0.0
	velocity = crash_context.current_velocity
	scoring.bail()
	trick.reset()
	flick.reset()
	trick_rotation_state.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	grab_amount = 0.0
	grab_tweak = Vector2.ZERO
	rail_pose = 0
	AudioManager.crash_feedback()
	animation_controller.trigger(SkierAnimationController.AnimationEvent.BAIL, 1.0, crash_context.lateral_bias)
	crashed.emit()
	state_changed.emit("Bail")
	return true

func _bail() -> void:
	var context := CrashContext.new()
	context.begin(
		CrashContext.Reason.LANDING_IMPACT,
		CrashContext.Source.LANDING,
		state,
		velocity,
		velocity,
		contact.average_normal,
		maxf(0.0, -velocity.dot(contact.average_normal)),
		angular_velocity.length(),
		float(landing_context.get("balance_error", 0.0)),
		0.0,
		signf(lateral_slip)
	)
	enter_crash(context)

func _landing_crash_context(result: Dictionary) -> CrashContext:
	var reason := CrashContext.Reason.LANDING_IMPACT
	match int(result.get("failure_reason", LandingSolver.FailureReason.NONE)):
		LandingSolver.FailureReason.UPRIGHT:
			reason = CrashContext.Reason.LANDING_UPRIGHT
		LandingSolver.FailureReason.ANGULAR:
			reason = CrashContext.Reason.LANDING_ANGULAR
		_:
			reason = CrashContext.Reason.LANDING_IMPACT
	var source := CrashContext.Source.RAIL if recent_rail_detach_time > 0.0 else CrashContext.Source.LANDING
	var source_state := State.GRIND if source == CrashContext.Source.RAIL else State.AIR
	var lateral_bias := signf(float(result.get("lateral_velocity", 0.0)))
	if absf(lateral_bias) < 0.05:
		lateral_bias = signf(angular_velocity.z)
	var context := CrashContext.new()
	context.begin(
		reason,
		source,
		source_state,
		velocity,
		velocity,
		contact.average_normal,
		float(result.get("impact", 0.0)),
		angular_velocity.length(),
		float(result.get("balance_error", 0.0)),
		recent_rail_detach_balance if source == CrashContext.Source.RAIL else 0.0,
		lateral_bias
	)
	return context

func _update_crash_stage_and_rest(delta: float) -> void:
	var release_end := animation_controller.profile.crash_release_duration
	var impact_end := release_end + animation_controller.profile.crash_impact_duration
	if crash_context.elapsed < release_end:
		crash_context.stage = CrashContext.Stage.RELEASE
	elif crash_context.elapsed < impact_end:
		crash_context.stage = CrashContext.Stage.IMPACT
	elif not crash_context.rest_detected:
		crash_context.stage = CrashContext.Stage.FALL
	var resting_candidate := (
		contact.grounded
		and crash_context.elapsed >= profile.crash_min_duration
		and velocity.length() <= profile.crash_rest_speed
		and angular_velocity.length() <= profile.crash_rest_angular_speed
	)
	if not crash_context.rest_detected:
		if resting_candidate:
			crash_context.rest_elapsed += delta
		else:
			crash_context.rest_elapsed = 0.0
		if crash_context.rest_elapsed >= profile.crash_rest_confirm_time or (contact.grounded and crash_context.elapsed >= profile.crash_max_duration):
			crash_context.rest_detected = true
			crash_context.rest_elapsed = 0.0
			crash_context.stage = CrashContext.Stage.REST
	else:
		crash_context.stage = CrashContext.Stage.REST
		crash_context.rest_elapsed += delta
		if crash_context.rest_elapsed >= profile.crash_rest_hold_time:
			_recover_from_bail()

func _clear_crash_state() -> void:
	crash_context.reset()
	bail_time = 0.0
	bail_recovering = false

func _evaluate_feature_crash_after_motion() -> void:
	var context := _collision_crash_evaluator.evaluate(
		last_collision_diagnostics,
		state,
		profile.feature_collision_min_speed,
		profile.feature_collision_min_normal_speed,
		profile.feature_collision_max_speed_retention,
		angular_velocity.length(),
		global_basis,
		velocity
	)
	if context != null:
		enter_crash(context)

func _recover_from_bail() -> void:
	bail_recovering = false
	_clear_landing_orientation_settle()
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
	_clear_crash_state()
	state_changed.emit("Ground")

func respawn_at(value: Transform3D) -> void:
	respawn_count += 1
	active_rail = null
	velocity = Vector3.ZERO
	_clear_landing_orientation_settle()
	angular_velocity = Vector3.ZERO
	global_transform = value
	global_position += Vector3.UP * 0.35
	state = State.AIR
	air_deliberate = false
	air_takeoff_type = SkierAnimationFrame.TakeoffType.NONE
	air_takeoff_charge = 0.0
	air_takeoff_upward_speed = 0.0
	air_reference_up = Vector3.UP
	wall_pin_time = 0.0
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	trick.reset()
	flick.reset()
	trick_rotation_state.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	rail_pose = 0
	rail_balance = 0.0
	rail_capture_blend_remaining = 0.0
	rail_entry_severity = 0.0
	bail_recovering = false
	recent_rail_detach_time = 0.0
	recent_rail_detach_balance = 0.0
	landing_feedback_armed = false
	landing_context = {}
	landing_control_multiplier = 1.0
	landing_control_recovery_rate = 0.0
	predicted_landing_time = -1.0
	predicted_landing_valid = false
	predicted_landing_normal = Vector3.UP
	predicted_landing_point = Vector3.ZERO
	contact = SkiContactSolver.new()
	last_collision_diagnostics.clear()
	last_collision_colliders.clear()
	last_speed_discontinuity = {}
	animation_frame.reset()
	_clear_crash_state()
	# Any authoritative respawn ends the active line. Preserve total score for
	# marker/course recovery, but never carry a combo multiplier into a new
	# physical attempt.
	scoring.reset_link()
	scoring.break_combo("respawn")
	AudioManager.stop_feedback()
	animation_controller.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
	state_changed.emit("Air")
	respawn_applied.emit(global_transform)

func set_recovery_frozen(value: bool) -> void:
	"""Freeze simulation/input while CourseRecovery performs its fade/respawn lifecycle."""
	recovery_frozen = value
	if value:
		velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func reset_for_benchmark(value: Transform3D, initial_velocity: Vector3 = Vector3.ZERO) -> void:
	"""Reset every motion subsystem to a reproducible benchmark baseline."""
	recovery_frozen = false
	active_rail = null
	velocity = initial_velocity
	_clear_landing_orientation_settle()
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
	rail_entry_severity = 0.0
	bail_time = 0.0
	bail_recovering = false
	recent_rail_detach_time = 0.0
	recent_rail_detach_balance = 0.0
	_clear_crash_state()
	grab_amount = 0.0
	grab_tweak = Vector2.ZERO
	grab_release_time = 0.0
	predicted_landing_time = -1.0
	predicted_landing_valid = false
	predicted_landing_normal = Vector3.UP
	predicted_landing_point = Vector3.ZERO
	landing_feedback_armed = false
	landing_context = {}
	landing_control_multiplier = 1.0
	landing_control_recovery_rate = 0.0
	air_deliberate = false
	air_takeoff_type = SkierAnimationFrame.TakeoffType.NONE
	air_takeoff_charge = 0.0
	air_takeoff_upward_speed = 0.0
	air_reference_up = Vector3.UP
	wall_pin_time = 0.0
	last_collision_diagnostics.clear()
	last_collision_colliders.clear()
	last_speed_discontinuity = {}
	trick_sample.reset()
	trick_command.reset()
	trick.reset()
	flick.reset()
	trick_rotation_state.reset()
	active_trick_kind = TrickCommand.Kind.NONE
	trick_phase = TrickCommand.PresentationPhase.NEUTRAL
	gesture_strength = 0.0
	if scoring != null:
		scoring.reset_run()
	if snow_vfx != null:
		snow_vfx.clear_transient_effects()
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
		var collider_layer: int = collider.collision_layer if collider is CollisionObject3D else 0
		var normal := collision.get_normal()
		var collider_asset_id := str(collider.get_meta("asset_id", "")) if collider is Node else ""
		var collider_asset_class := str(collider.get_meta("asset_class", "")) if collider is Node else ""
		var collider_policy := str(collider.get_meta("collision_policy", "")) if collider is Node else ""
		var incoming_normal_speed := maxf(0.0, -velocity_before_motion.dot(normal))
		var resolved_velocity := velocity_before_motion.slide(normal)
		var resolved_speed := resolved_velocity.length()
		var collision_speed_loss := maxf(0.0, speed_before - resolved_speed)
		last_collision_colliders.append(collider.name if collider is Node else "<unnamed>")
		if incoming_normal_speed < 2.0 and not discontinuity:
			continue
		last_collision_diagnostics.append({
				"collider": collider.name if collider is Node else "<unnamed>",
				"asset_id": collider_asset_id,
				"asset_class": collider_asset_class,
				"collision_policy": collider_policy,
				"normal": normal,
				"position": collision.get_position(),
				"collider_layer": collider_layer,
				"velocity_before": velocity_before_motion,
				"velocity_after": resolved_velocity,
				"speed_before": speed_before,
				"speed_after": resolved_speed,
				"speed_loss": collision_speed_loss,
				"speed_retention": resolved_speed / maxf(speed_before, 0.01),
				"incoming_normal_speed": incoming_normal_speed,
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
		"surface_class": SkiContactSolver.SurfaceClass.keys()[contact.surface_class],
		"snow_contact": contact.surface_class == SkiContactSolver.SurfaceClass.SNOW,
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
		"trick_rotation": trick_rotation_state.snapshot(),
		"rail": active_rail.name if active_rail != null else "—",
		"rail_balance": rail_balance,
		"rail_progress": clampf(rail_offset / maxf(active_rail.path_length, 0.01), 0.0, 1.0) if active_rail != null else 0.0,
		"rail_distance_to_end": _rail_distance_to_end(),
		"rail_entry_severity": rail_entry_severity,
		"rail_pose": rail_pose,
		"predicted_landing_time": predicted_landing_time,
		"predicted_landing_valid": predicted_landing_valid,
		"landing_feedback_armed": landing_feedback_armed,
		"landing_control_multiplier": landing_control_multiplier,
		"landing": {
			"impact_speed": float(landing_context.get("impact_speed", 0.0)),
			"impact_severity": float(landing_context.get("impact_severity", 0.0)),
			"balance_error": float(landing_context.get("balance_error", 0.0)),
			"ski_alignment_error": float(landing_context.get("ski_alignment_error", 0.0)),
			"body_roll_error": float(landing_context.get("body_roll_error", 0.0)),
			"body_pitch_error": float(landing_context.get("body_pitch_error", 0.0)),
			"rotation_error": float(landing_context.get("rotation_error", 0.0)),
			"active": bool(landing_context.get("active", false)),
		},
		"crash": crash_context.snapshot(),
		"crash_equipment": animation_controller.equipment_attachment_snapshot() if animation_controller != null else {},
		"recovery_frozen": recovery_frozen,
		"respawn_count": respawn_count,
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
			"style": TrickController.STYLE_NAMES[trick.style_pose],
			"trick_text": trick.live_name() if trick != null else "",
			"yaw_degrees": int(round(rad_to_deg(absf(trick.accumulated_rotation.y)))) if trick != null else 0,
			"flip_degrees": int(round(rad_to_deg(absf(trick.accumulated_rotation.x)))) if trick != null else 0,
			"cork_degrees": int(round(rad_to_deg(maxf(absf(trick.accumulated_rotation.y), absf(trick.accumulated_rotation.z))))) if trick != null else 0,
			"accumulated_rotation": trick.accumulated_rotation if trick != null else Vector3.ZERO,
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
	animation_controller = SkierVisualScene.instantiate() as SkierAnimationController
	animation_controller.name = "SkierAnimationController"
	visual_root = animation_controller
	add_child(animation_controller)

func _build_snow_vfx() -> void:
	snow_vfx = SkiSnowVFX.new()
	snow_vfx.name = "SkiSnowVFX"
	add_child(snow_vfx)

func _build_contact_shadow() -> void:
	contact_shadow = MeshInstance3D.new()
	contact_shadow.name = "ContactShadow"
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_shadow.visibility_range_begin = 0.0
	contact_shadow.visibility_range_end = 120.0
	contact_shadow.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.2, 2.2)
	plane.orientation = PlaneMesh.FACE_Y
	contact_shadow.mesh = plane
	contact_shadow_material = ShaderMaterial.new()
	contact_shadow_material.shader = preload("res://shaders/contact_shadow.gdshader")
	contact_shadow_material.set_shader_parameter("shadow_color", Color(0.08, 0.12, 0.18, 1.0))
	contact_shadow_material.set_shader_parameter("shadow_opacity", 0.52)
	contact_shadow.material_override = contact_shadow_material
	contact_shadow.top_level = true
	add_child(contact_shadow)

func _update_contact_shadow(_delta: float) -> void:
	if contact_shadow == null or contact_shadow_material == null:
		return
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if not contact_shadow.is_inside_tree() or contact_shadow.is_queued_for_deletion():
		return
	var tree := get_tree()
	if tree == null or tree.is_queued_for_deletion():
		return
	var world := get_world_3d()
	if world == null:
		contact_shadow.visible = false
		return
	var ground_pos := Vector3.ZERO
	var ground_normal := Vector3.UP
	var found := false
	if contact.grounded and contact.average_hit_position.length_squared() > 0.001:
		ground_pos = contact.average_hit_position
		ground_normal = contact.average_normal.normalized() if contact.average_normal.length_squared() > 0.001 else Vector3.UP
		found = true
	else:
		# Airborne: raycast down to find snow for height cue.
		var space := world.direct_space_state
		if space != null:
			var from := global_position + Vector3.UP * 0.4
			var to := global_position + Vector3.DOWN * 12.0
			var query := PhysicsRayQueryParameters3D.create(from, to, 1)
			query.exclude = [get_rid()]
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				ground_pos = hit.position as Vector3
				ground_normal = hit.normal as Vector3
				found = true
			else:
				# Fallback to vertical projection onto pitched piste plane.
				var n := ParkLayout.snow_normal()
				var plane_dist := (global_position - ParkLayout.snow_at(global_position.x, global_position.z)).dot(n)
				ground_pos = global_position - n * plane_dist
				ground_normal = n
				found = true
		else:
			var n := ParkLayout.snow_normal()
			var plane_dist := (global_position - ParkLayout.snow_at(global_position.x, global_position.z)).dot(n)
			ground_pos = global_position - n * plane_dist
			ground_normal = n
			found = true
	if not found:
		contact_shadow.visible = false
		return
	var to_skier := global_position - ground_pos
	var height := to_skier.dot(ground_normal)
	height = clampf(height, 0.0, 12.0)
	# Restrained fade: visible when near ground, fades gracefully before becoming a distant blob.
	var height_alpha := clampf(1.0 - smoothstep(1.2, 9.5, height), 0.0, 1.0)
	var confidence_alpha := clampf(contact.confidence, 0.0, 1.0) if state == State.GROUND else 0.85
	var alpha := height_alpha * lerpf(0.45, 0.72, confidence_alpha) * 0.52
	if alpha < 0.02 or height > 9.0:
		contact_shadow.visible = false
		return
	contact_shadow.visible = true
	# Position slightly above snow to avoid z-fighting, oriented to snow plane.
	var downhill := ParkLayout.downhill()
	if ground_normal.length_squared() < 0.001:
		ground_normal = Vector3.UP
	if downhill.length_squared() < 0.001:
		downhill = Vector3.FORWARD
	# Align plane to ground: Y = ground_normal
	var basis := Basis.looking_at(downhill, ground_normal)
	contact_shadow.global_transform = Transform3D(basis, ground_pos + ground_normal * 0.018)
	# Size grows slightly with height to mimic softer penumbra, but restrained (use scale, not mesh mutation).
	var size_factor := lerpf(1.0, 1.45, clampf(height / 7.0, 0.0, 1.0))
	contact_shadow.scale = Vector3(size_factor, 1.0, size_factor)
	contact_shadow_material.set_shader_parameter("shadow_opacity", alpha)

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
	var prediction := {
		"time": -1.0,
		"valid": false,
		"normal": Vector3.UP,
		"point": Vector3.ZERO,
	}
	if state != State.BAIL:
		prediction = _predict_landing()
	predicted_landing_time = float(prediction.time)
	predicted_landing_valid = bool(prediction.valid)
	predicted_landing_normal = prediction.normal as Vector3
	predicted_landing_point = prediction.point as Vector3
	var predicted_landing := predicted_landing_time
	var landing_release := 0.0
	if predicted_landing >= 0.0 and predicted_landing < animation_controller.profile.landing_anticipation_time:
		landing_release = 1.0 - predicted_landing / animation_controller.profile.landing_anticipation_time
	animation_frame.locomotion_state = state
	animation_frame.speed_mps = velocity.length()
	animation_frame.speed_ratio = clampf(velocity.length() / profile.maximum_speed, 0.0, 1.0)
	animation_frame.edge = edge_amount
	animation_frame.turn_input = steering_input
	animation_frame.turn_rate = -edge_amount * effective_steer_rate * current_carve_ratio
	animation_frame.skid = lateral_slip
	animation_frame.skid_ratio = skid_amount
	animation_frame.carve_force = carve_force
	animation_frame.lateral_acceleration = -signf(edge_amount) * carve_force
	animation_frame.carve_ratio = current_carve_ratio
	animation_frame.heading_velocity_delta = deg_to_rad(heading_travel_angle_degrees)
	animation_frame.skier_heading = -global_basis.z
	var travel_heading := velocity.slide(contact.average_normal)
	animation_frame.velocity_heading = travel_heading.normalized() if travel_heading.length_squared() > 0.001 else -global_basis.z
	animation_frame.slope_angle = deg_to_rad(slope_angle_degrees)
	animation_frame.grounded = state == State.GROUND and contact.grounded
	animation_frame.tuck = tuck_amount
	animation_frame.braking = braking
	animation_frame.compression = clampf(jump_charge / maxf(profile.maximum_jump_charge, 0.001), 0.0, 1.0)
	animation_frame.contact_confidence = contact.confidence
	animation_frame.ground_normal = contact.average_normal
	animation_frame.seat_distance = 0.35 + profile.ground_attach_height
	animation_frame.left_ground_distance = contact.left_distance
	animation_frame.right_ground_distance = contact.right_distance
	animation_frame.left_normal = contact.left_normal
	animation_frame.right_normal = contact.right_normal
	animation_frame.left_hit_position = contact.left_hit_position
	animation_frame.right_hit_position = contact.right_hit_position
	animation_frame.left_grounded = contact.left_grounded
	animation_frame.right_grounded = contact.right_grounded
	animation_frame.left_contact_confidence = contact.left_contact_confidence
	animation_frame.right_contact_confidence = contact.right_contact_confidence
	animation_frame.left_front_valid = contact.left_front_valid
	animation_frame.left_rear_valid = contact.left_rear_valid
	animation_frame.right_front_valid = contact.right_front_valid
	animation_frame.right_rear_valid = contact.right_rear_valid
	animation_frame.left_front_position = contact.left_front_position
	animation_frame.left_rear_position = contact.left_rear_position
	animation_frame.right_front_position = contact.right_front_position
	animation_frame.right_rear_position = contact.right_rear_position
	animation_frame.left_front_normal = contact.left_front_normal
	animation_frame.left_rear_normal = contact.left_rear_normal
	animation_frame.right_front_normal = contact.right_front_normal
	animation_frame.right_rear_normal = contact.right_rear_normal
	animation_frame.angular_velocity = angular_velocity
	var animation_body_up := global_basis.y
	animation_frame.body_up_valid = _finite_vector(animation_body_up) and animation_body_up.length_squared() > 0.000001
	animation_frame.body_up = animation_body_up.normalized() if animation_frame.body_up_valid else Vector3.UP
	var animation_ski_forward := -global_basis.z
	animation_frame.ski_forward_valid = _finite_vector(animation_ski_forward) and animation_ski_forward.length_squared() > 0.000001
	animation_frame.ski_forward = animation_ski_forward.normalized() if animation_frame.ski_forward_valid else Vector3.FORWARD
	var animation_ski_up := global_basis.y
	animation_frame.ski_up_valid = _finite_vector(animation_ski_up) and animation_ski_up.length_squared() > 0.000001
	animation_frame.ski_up = animation_ski_up.normalized() if animation_frame.ski_up_valid else Vector3.UP
	var world_angular_velocity := global_basis * angular_velocity
	animation_frame.angular_velocity_world_valid = _finite_vector(world_angular_velocity)
	animation_frame.angular_velocity_world = world_angular_velocity if animation_frame.angular_velocity_world_valid else Vector3.ZERO
	animation_frame.vertical_velocity = velocity.y
	animation_frame.air_time = air_time
	animation_frame.takeoff_type = air_takeoff_type if state == State.AIR else SkierAnimationFrame.TakeoffType.NONE
	animation_frame.takeoff_charge = air_takeoff_charge if state == State.AIR else 0.0
	animation_frame.takeoff_upward_speed = air_takeoff_upward_speed if state == State.AIR else 0.0
	animation_frame.air_upward_velocity = velocity.dot(air_reference_up) if state == State.AIR else 0.0
	animation_frame.predicted_landing_time = predicted_landing
	animation_frame.predicted_landing_normal = predicted_landing_normal
	animation_frame.predicted_landing_point = predicted_landing_point
	animation_frame.predicted_landing_valid = predicted_landing_valid
	animation_frame.landing_impact_speed = float(landing_context.get("impact_speed", 0.0))
	animation_frame.landing_impact_severity = float(landing_context.get("impact_severity", 0.0))
	animation_frame.landing_balance_error = float(landing_context.get("balance_error", 0.0))
	animation_frame.landing_ski_alignment_error = float(landing_context.get("ski_alignment_error", 0.0))
	animation_frame.landing_body_roll_error = float(landing_context.get("body_roll_error", 0.0))
	animation_frame.landing_body_pitch_error = float(landing_context.get("body_pitch_error", 0.0))
	animation_frame.landing_rotation_error = float(landing_context.get("rotation_error", 0.0))
	animation_frame.landing_lateral_velocity = float(landing_context.get("lateral_velocity", 0.0))
	animation_frame.landing_forward_velocity = float(landing_context.get("forward_velocity", 0.0))
	animation_frame.landing_air_time = float(landing_context.get("air_time", 0.0))
	animation_frame.landing_surface_normal = landing_context.get("surface_normal", contact.average_normal) as Vector3
	animation_frame.landing_outcome = int(landing_context.get("outcome", 0))
	animation_frame.landing_event_active = bool(landing_context.get("active", false))
	animation_frame.grab_pose = trick.grab_pose
	animation_frame.style_pose = trick.style_pose
	animation_frame.style_amount = trick_command.style_amount
	animation_frame.switch_stance = velocity.dot(-global_basis.z) < 0.0
	animation_frame.rail_speed = absf(rail_speed) if state == State.GRIND else 0.0
	animation_frame.rail_balance = rail_balance if state == State.GRIND else 0.0
	animation_frame.rail_type = active_rail.rail_type if active_rail != null else 0
	animation_frame.rail_pose = rail_pose if state == State.GRIND else 0
	animation_frame.rail_direction = (active_rail.tangent_at(rail_offset) * rail_direction) if active_rail != null and state == State.GRIND else -global_basis.z
	animation_frame.rail_up = Vector3.UP
	animation_frame.rail_progress = clampf(rail_offset / maxf(active_rail.path_length, 0.01), 0.0, 1.0) if active_rail != null and state == State.GRIND else 0.0
	animation_frame.rail_distance_to_end = _rail_distance_to_end() if state == State.GRIND else 999.0
	animation_frame.rail_entry_severity = rail_entry_severity if state == State.GRIND else 0.0
	animation_frame.rail_approach_anticipation = _scan_rail_approach()
	animation_frame.trick_kind = active_trick_kind
	animation_frame.trick_phase = TrickCommand.PresentationPhase.LANDING if landing_release > 0.58 else trick_phase
	animation_frame.gesture_strength = gesture_strength
	animation_frame.gesture_direction = trick_sample.right_stick
	animation_frame.left_trigger = trick_sample.left_trigger
	animation_frame.right_trigger = trick_sample.right_trigger
	animation_frame.grab_amount = grab_amount
	animation_frame.grab_input_strength = grab_amount
	animation_frame.grab_hold_time = trick.grab_seconds
	animation_frame.grab_release_time = grab_release_time
	animation_frame.grab_tweak = grab_tweak
	var rotation_amount := maxf(absf(trick.accumulated_rotation.x), maxf(absf(trick.accumulated_rotation.y), absf(trick.accumulated_rotation.z)))
	animation_frame.rotation_progress = fmod(rotation_amount / TAU, 1.0)
	animation_frame.trick_active = trick.active
	animation_frame.trick_intent = (
		trick.had_trick_intent
		or trick_phase in [TrickCommand.PresentationPhase.SETUP, TrickCommand.PresentationPhase.RELEASE]
		or active_trick_kind not in [TrickCommand.Kind.NONE, TrickCommand.Kind.POP]
	)
	animation_frame.rotation_accumulated = (
		trick.accumulated_rotation
		if trick.active
		else landing_context.get("rotation_accumulated", Vector3.ZERO) as Vector3
	)
	animation_frame.rotation_residual = (
		trick.rotation_residual_vector()
		if trick.active and trick.had_trick_intent
		else landing_context.get("rotation_residual", Vector3.ZERO) as Vector3
	)
	animation_frame.rotation_compactness = trick_rotation_state.compactness if trick_rotation_state.active else 0.5
	animation_frame.rotation_inertia_scale = trick_rotation_state.inertia_scale if trick_rotation_state.active else 1.0
	animation_frame.rotation_axis_local = trick_rotation_state.primary_axis_local if trick_rotation_state.active else Vector3.ZERO
	animation_frame.rotation_axis_weights = trick_rotation_state.axis_weights if trick_rotation_state.active else Vector3.ZERO
	animation_frame.crash_reason = crash_context.reason
	animation_frame.crash_stage = crash_context.stage
	animation_frame.crash_elapsed = crash_context.elapsed
	animation_frame.crash_impact_normal = crash_context.impact_normal
	animation_frame.crash_incoming_velocity = crash_context.incoming_velocity
	animation_frame.crash_current_velocity = crash_context.current_velocity
	animation_frame.crash_impact_speed = crash_context.impact_speed
	animation_frame.crash_lateral_bias = crash_context.lateral_bias
	animation_frame.crash_angular_speed = crash_context.angular_speed
	animation_frame.crash_rest_detected = crash_context.rest_detected
	var upright_dot := global_basis.y.normalized().dot(predicted_landing_normal.normalized()) if predicted_landing_valid else 1.0
	var upright_warning := 1.0 - smoothstep(profile.recoverable_upright_dot, profile.sketchy_upright_dot, upright_dot)
	var angular_ratio := angular_velocity.length() / maxf(profile.maximum_angular_speed, 0.01)
	var angular_warning := smoothstep(profile.bail_angular_ratio * 0.55, profile.bail_angular_ratio, angular_ratio)
	animation_frame.pre_bail_weight = clampf(maxf(upright_warning, angular_warning) * landing_release, 0.0, 1.0) if state == State.AIR else 0.0
	var balance_side := signf(angular_velocity.z)
	if absf(balance_side) < 0.05:
		balance_side = signf(velocity.dot(global_basis.x))
	animation_frame.pre_bail_side = balance_side
	animation_controller.apply_frame(animation_frame, delta)
	var animation_snapshot := animation_controller.debug_snapshot()
	trick.set_grab_contact(
		float(animation_snapshot.get("grab_contact_weight", 0.0)),
		str(animation_snapshot.get("grab_phase", "IDLE")),
		delta
	)
	if animation_controller.is_landing_idle() and bool(landing_context.get("active", false)):
		landing_context["active"] = false

func _predict_landing_time() -> float:
	return float(_predict_landing().time)

func _predict_landing() -> Dictionary:
	var result := {
		"time": -1.0,
		"valid": false,
		"normal": Vector3.UP,
		"point": Vector3.ZERO,
	}
	if state != State.AIR:
		return result
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
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			result.time = elapsed + step
			result.valid = true
			result.normal = (hit.normal as Vector3).normalized() if (hit.normal as Vector3).length_squared() > 0.0001 else Vector3.UP
			result.point = hit.position as Vector3
			return result
		position = next_position
		predicted_velocity = next_velocity
		elapsed += step
	return result

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
		_debug_line_world(point, point + contact.average_normal * 1.2)
	if contact.left_grounded:
		_debug_line_world(contact.left_hit_position, contact.left_hit_position + contact.left_normal * 0.8)
		var left_nose := animation_debug_landmark(&"left_ski_nose")
		var left_tail := animation_debug_landmark(&"left_ski_tail")
		_debug_line_world((left_nose + left_tail) * 0.5, contact.left_hit_position)
	if contact.right_grounded:
		_debug_line_world(contact.right_hit_position, contact.right_hit_position + contact.right_normal * 0.8)
		var right_nose := animation_debug_landmark(&"right_ski_nose")
		var right_tail := animation_debug_landmark(&"right_ski_tail")
		_debug_line_world((right_nose + right_tail) * 0.5, contact.right_hit_position)
	var animation_debug := animation_controller.debug_snapshot()
	var landmarks := animation_debug.get("silhouette_landmarks", {}) as Dictionary
	var pelvis_world := landmarks.get("pelvis", global_position) as Vector3
	var pelvis_target := animation_debug.get("pelvis_target_world", pelvis_world) as Vector3
	_debug_line_world(pelvis_world, pelvis_target)
	var compression_origin := global_position + global_basis.y * 1.7
	var left_compression := float(animation_debug.get("left_leg_compression", 0.0))
	var right_compression := float(animation_debug.get("right_leg_compression", 0.0))
	_debug_line_world(compression_origin - global_basis.x * 0.18, compression_origin - global_basis.x * 0.18 + global_basis.y * left_compression * 0.45)
	_debug_line_world(compression_origin + global_basis.x * 0.18, compression_origin + global_basis.x * 0.18 + global_basis.y * right_compression * 0.45)
	var direction_origin := global_position + global_basis.y
	_debug_line_world(direction_origin, direction_origin - global_basis.z * 1.8)
	_debug_line_world(direction_origin, direction_origin + velocity * 0.15)
	if predicted_landing_valid:
		_debug_line_world(direction_origin, predicted_landing_point)
	if int(animation_debug.get("grab_target_count", 0)) > 0:
		var left_target := animation_debug.get("grab_target_left", Vector3.ZERO) as Vector3
		var right_target := animation_debug.get("grab_target_right", Vector3.ZERO) as Vector3
		if str(animation_debug.get("grab_hand", "NONE")) in ["LEFT", "BOTH"]:
			_debug_line_world(landmarks.get("left_hand", global_position) as Vector3, left_target)
		if str(animation_debug.get("grab_hand", "NONE")) in ["RIGHT", "BOTH"]:
			_debug_line_world(landmarks.get("right_hand", global_position) as Vector3, right_target)
	debug_mesh.surface_end()

func animation_debug_landmark(name: StringName) -> Vector3:
	if animation_controller == null:
		return global_position
	var snapshot := animation_controller.debug_snapshot()
	var landmarks := snapshot.get("silhouette_landmarks", {}) as Dictionary
	return landmarks.get(name, global_position) as Vector3

func _debug_line_world(from_world: Vector3, to_world: Vector3) -> void:
	debug_mesh.surface_add_vertex(to_local(from_world))
	debug_mesh.surface_add_vertex(to_local(to_world))

func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

var last_physics_delta: float:
	get:
		return 1.0 / float(Engine.physics_ticks_per_second)
