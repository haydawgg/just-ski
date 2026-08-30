class_name SkiCameraController
extends Node3D

## Phase 4 camera: larger skier framing, carve-aware look blending, and
## per-channel smoothing (position/yaw/pitch/FOV/look-ahead/surface-up)
## so terrain suspension stays readable while the camera remains calm.
## State-aware profiles (GROUND/AIR/LANDING/RAIL/CRASH) layer deltas onto
## the speed-scaled base; heading blend is trajectory-only while airborne
## or crashing so spins/flips never wobble the camera.

enum CameraState { GROUND, AIR, LANDING, RAIL, CRASH }

@export_group("Framing")
@export var follow_distance := 4.3
@export var follow_height := 1.45
@export var speed_distance_gain := 0.018
@export var speed_distance_cap := 0.62
@export var speed_distance_response := 1.35
@export var speed_height_gain := 0.005
@export var speed_height_cap := 0.16
@export var speed_height_response := 1.6
@export var look_height_offset := 0.12
@export var air_height := 0.82
@export var air_height_rise_rate := 5.0
@export var air_height_fall_rate := 7.0
@export var air_vertical_dead_zone := 0.5
@export var air_vertical_anchor_response := 3.4

@export_group("Position Spring")
@export var spring_strength := 14.0
@export var damping := 8.5
@export var vertical_spring_strength := 10.0
@export var vertical_damping := 9.0

@export_group("Orientation")
@export var yaw_rate_slow := 6.0
@export var yaw_rate_fast := 3.5
@export var yaw_speed_reference := 30.0
@export var pitch_rate := 3.0
@export var trajectory_heading_speed_threshold := 1.0
@export var trajectory_heading_full_speed := 4.0
@export var ground_heading_response := 2.8

@export_group("Collision Safety")
@export var collision_clearance := 0.35
@export var collision_probe_height := 1.0
@export var minimum_camera_distance := 3.35
@export var maximum_camera_distance := 7.4
@export var minimum_camera_up_offset := 0.7
@export var minimum_behind_distance := 2.6
@export var collision_reframe_lift := 1.35
@export var collision_shoulder_offset := 1.25
@export var collision_correction_speed := 8.0
@export var maximum_position_speed := 30.0

@export_group("Carve Look")
@export var look_heading_weight_min := 0.15
@export var look_heading_weight_gain := 0.35
@export var heading_angle_reference := 45.0
@export var landing_heading_weight := 0.05
@export var turn_look_ahead_gain := 1.8
@export var predicted_landing_look_weight := 0.38

@export_group("Look-ahead & FOV")
@export var look_ahead_min := 3.0
@export var look_ahead_max := 15.0
@export var look_ahead_gain := 0.30
@export var look_ahead_rate := 4.0
@export var base_fov := 68.0
@export var speed_fov_gain := 7.0
@export var fov_speed_reference := 30.0
@export var fov_rate := 4.0

@export_group("Turn Bank")
@export_range(0.0, 0.3) var turn_bank_share := 0.15
@export var skier_bank_reference_degrees := 28.0
@export var turn_bank_limit_degrees := 5.0
@export var turn_bank_response := 3.2

@export_group("Stabilization")
@export var surface_up_rate := 3.5

@export_group("State Profiles")
@export var profile_rate := 3.0
@export var landing_hold_time := 0.35
@export var landing_min_air_time := 0.25
@export var air_distance_delta := 0.6
@export var air_height_delta := 0.35
@export var air_fov_delta := 2.0
@export var air_yaw_scale := 0.7
@export var air_look_ahead := 7.0
@export var landing_distance_delta := 0.2
@export var landing_height_delta := 0.1
@export var landing_fov_delta := 1.0
@export var landing_yaw_scale := 0.8
@export var landing_look_ahead := 6.0
@export var rail_distance_delta := -0.1
@export var crash_distance_delta := 0.8
@export var crash_height_delta := 0.3
@export var crash_fov_delta := -2.0
@export var crash_yaw_scale := 0.45
@export var crash_look_ahead := 4.0

var target: CharacterBody3D
var camera: Camera3D
var camera_state := CameraState.GROUND
var spring_velocity_horizontal := Vector3.ZERO
var spring_velocity_vertical := Vector3.ZERO
var _filtered_surface_up := Vector3.UP
var _yaw_dir := Vector3.FORWARD
var _pitch := 0.0
var _smoothed_air_height := 0.0
var _air_anchor_height := 0.0
var _air_anchor_valid := false
var _smoothed_speed_distance := 0.0
var _smoothed_speed_height := 0.0
var _smoothed_look_ahead := look_ahead_min
var _trajectory_dir := Vector3.FORWARD
var _air_time := 0.0
var _landing_timer := 0.0
var _profile_distance := 0.0
var _profile_height := 0.0
var _profile_fov := 0.0
var _profile_yaw_scale := 1.0
var _profile_look_ahead := 0.0
var _smoothed_heading_weight := 0.0
var _smoothed_bank := 0.0
var _last_stable_camera_position := Vector3.ZERO
var _desired_camera_position := Vector3.ZERO
var _desired_camera_forward := Vector3.FORWARD
var _debug_horizontal_velocity := Vector3.ZERO
var _debug_facing_forward := Vector3.FORWARD
var _collision_reframed := false

func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = base_fov
	camera.near = 0.08
	add_child(camera)

func set_target(value: CharacterBody3D) -> void:
	target = value
	reset_immediate()

func reset_immediate() -> void:
	if target == null:
		return
	var skier := target as SkierController
	var up := Vector3.UP
	if skier != null and skier.state in [SkierController.State.GROUND, SkierController.State.GRIND] and skier.contact.average_normal.length_squared() > 0.01:
		up = skier.contact.average_normal.normalized()
	var forward := -target.global_basis.z
	var speed := target.velocity.length()
	_filtered_surface_up = up
	var horizontal := (forward - up * forward.dot(up))
	_yaw_dir = horizontal.normalized() if horizontal.length_squared() > 0.001 else Vector3.FORWARD
	_pitch = atan2(-forward.dot(up), maxf(forward.dot(_yaw_dir), 0.0001))
	global_position = target.global_position - _yaw_dir * follow_distance + up * follow_height
	_last_stable_camera_position = global_position
	_desired_camera_position = global_position
	_debug_horizontal_velocity = target.velocity.slide(up)
	_debug_facing_forward = _yaw_dir
	spring_velocity_horizontal = Vector3.ZERO
	spring_velocity_vertical = Vector3.ZERO
	_smoothed_air_height = air_height if (skier != null and skier.state == SkierController.State.AIR) else 0.0
	_air_anchor_height = target.global_position.dot(up)
	_air_anchor_valid = skier != null and skier.state == SkierController.State.AIR
	_smoothed_speed_distance = clampf(speed * speed_distance_gain, 0.0, speed_distance_cap)
	_smoothed_speed_height = clampf(speed * speed_height_gain, 0.0, speed_height_cap)
	_smoothed_look_ahead = clampf(speed * look_ahead_gain, look_ahead_min, look_ahead_max)
	_desired_camera_forward = global_position.direction_to(target.global_position + _yaw_dir * _smoothed_look_ahead + up * look_height_offset)
	var planar := target.velocity.slide(up)
	_trajectory_dir = planar.normalized() if planar.length() > trajectory_heading_speed_threshold else _yaw_dir
	_air_time = 0.0
	_landing_timer = 0.0
	_smoothed_bank = 0.0
	if skier != null:
		match skier.state:
			SkierController.State.AIR:
				camera_state = CameraState.AIR
			SkierController.State.GRIND:
				camera_state = CameraState.RAIL
			SkierController.State.BAIL:
				camera_state = CameraState.CRASH
			_:
				camera_state = CameraState.GROUND
	else:
		camera_state = CameraState.GROUND
	camera.fov = base_fov + clampf(speed / fov_speed_reference, 0.0, 1.0) * speed_fov_gain
	_update_profile(skier, 1000.0)
	look_at(target.global_position + _yaw_dir * _smoothed_look_ahead + up * look_height_offset, Vector3.UP)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var frame_start_position := global_position
	var skier := target as SkierController
	var speed := target.velocity.length()

	var raw_surface_up := Vector3.UP
	if skier != null and skier.state in [SkierController.State.GROUND, SkierController.State.GRIND] and skier.contact.average_normal.length_squared() > 0.01:
		raw_surface_up = skier.contact.average_normal.normalized()
	_filtered_surface_up = _slerp_direction(_filtered_surface_up, raw_surface_up, 1.0 - exp(-surface_up_rate * delta))
	var up := _filtered_surface_up

	var previous_camera_state := camera_state
	_update_camera_state(skier, delta)
	_update_profile(skier, delta)
	if camera_state == CameraState.AIR and previous_camera_state != CameraState.AIR:
		_air_anchor_height = target.global_position.dot(up)
		_air_anchor_valid = true
	elif camera_state != CameraState.AIR:
		_air_anchor_valid = false

	var planar := target.velocity.slide(up)
	var planar_speed := planar.length()
	var facing := (-target.global_basis.z).slide(up)
	if facing.length_squared() > 0.001:
		facing = facing.normalized()
	else:
		facing = _trajectory_dir
	var velocity_heading := planar.normalized() if planar_speed > trajectory_heading_speed_threshold else _trajectory_dir
	if camera_state in [CameraState.AIR, CameraState.CRASH]:
		if planar_speed > trajectory_heading_speed_threshold:
			_trajectory_dir = velocity_heading
	else:
		var velocity_weight := smoothstep(
			trajectory_heading_speed_threshold,
			maxf(trajectory_heading_full_speed, trajectory_heading_speed_threshold + 0.01),
			planar_speed
		)
		var stable_heading_target := _slerp_direction(facing, velocity_heading, velocity_weight)
		_trajectory_dir = _slerp_direction(_trajectory_dir, stable_heading_target, 1.0 - exp(-ground_heading_response * delta))
	_debug_horizontal_velocity = planar
	_debug_facing_forward = facing
	var travel := _trajectory_dir.slide(up)
	if travel.length_squared() < 0.05:
		travel = (-target.global_basis.z).slide(up).normalized()
	if travel.length_squared() < 0.05:
		travel = Vector3.FORWARD

	var air_target := 0.0
	if skier != null and skier.state == SkierController.State.AIR:
		air_target = air_height
	var air_rate := air_height_rise_rate if air_target > _smoothed_air_height else air_height_fall_rate
	_smoothed_air_height = lerpf(_smoothed_air_height, air_target, 1.0 - exp(-air_rate * delta))
	var framing_target := target.global_position
	if camera_state == CameraState.AIR:
		framing_target = _air_framing_target(target.global_position, up, delta)

	var speed_distance_target := clampf(speed * speed_distance_gain, 0.0, speed_distance_cap)
	var speed_height_target := clampf(speed * speed_height_gain, 0.0, speed_height_cap)
	_smoothed_speed_distance = lerpf(_smoothed_speed_distance, speed_distance_target, 1.0 - exp(-speed_distance_response * delta))
	_smoothed_speed_height = lerpf(_smoothed_speed_height, speed_height_target, 1.0 - exp(-speed_height_response * delta))
	var distance := follow_distance + _smoothed_speed_distance + _profile_distance
	var desired_height := follow_height + _smoothed_speed_height + _smoothed_air_height + _profile_height
	var desired := framing_target - travel * distance + up * desired_height
	_desired_camera_position = desired
	var error := desired - global_position
	var error_vertical := up * error.dot(up)
	var error_horizontal := error - error_vertical
	spring_velocity_horizontal += (error_horizontal * spring_strength - spring_velocity_horizontal * damping) * delta
	spring_velocity_vertical += (error_vertical * vertical_spring_strength - spring_velocity_vertical * vertical_damping) * delta
	global_position += (spring_velocity_horizontal + spring_velocity_vertical) * delta
	var pre_collision_position := global_position
	var collision_candidate := _avoid_collision(target.global_position + up * collision_probe_height, global_position, up, travel)
	var collision_safe := collision_candidate
	if _collision_reframed:
		# Reframing is a camera presentation change, not a teleport. Blend the
		# safe candidate from the spring position before enforcing hard clearance.
		collision_safe = pre_collision_position.lerp(collision_candidate, 1.0 - exp(-collision_correction_speed * delta))
	var stabilized := _stabilize_camera_position(collision_safe, up, travel)
	var correction := stabilized - pre_collision_position
	var correction_limit := collision_correction_speed * delta
	if correction.length() > correction_limit and correction_limit > 0.0:
		stabilized = pre_collision_position + correction.normalized() * correction_limit
	global_position = _stabilize_camera_position(stabilized, up, travel)
	var frame_translation := global_position - frame_start_position
	var frame_translation_limit := maximum_position_speed * delta
	if frame_translation.length() > frame_translation_limit and frame_translation_limit > 0.0:
		global_position = frame_start_position + frame_translation.normalized() * frame_translation_limit
	# Translation limiting must never erode the minimum playable frame.
	global_position = _stabilize_camera_position(global_position, up, travel)

	var turn_look_ahead := 0.0
	if skier != null and camera_state in [CameraState.GROUND, CameraState.LANDING]:
		turn_look_ahead = clampf(
			absf(skier.heading_travel_angle_degrees) / maxf(heading_angle_reference, 1.0) * turn_look_ahead_gain,
			0.0,
			turn_look_ahead_gain
		)
	var look_ahead_target := maxf(clampf(speed * look_ahead_gain, look_ahead_min, look_ahead_max) + turn_look_ahead, _profile_look_ahead)
	_smoothed_look_ahead = lerpf(_smoothed_look_ahead, look_ahead_target, 1.0 - exp(-look_ahead_rate * delta))
	var look_dir := travel
	if skier != null and _smoothed_heading_weight > 0.005:
		var heading := (-target.global_basis.z).slide(up).normalized()
		if heading.length_squared() > 0.05:
			look_dir = _slerp_direction(travel, heading, _smoothed_heading_weight)
	var look_target := framing_target + look_dir * _smoothed_look_ahead + up * look_height_offset
	if skier != null and camera_state == CameraState.AIR and skier.predicted_landing_valid and skier.velocity.dot(up) < 0.0:
		var landing_weight := 1.0 - clampf(skier.predicted_landing_time / 0.75, 0.0, 1.0)
		landing_weight = smoothstep(0.0, 1.0, landing_weight) * predicted_landing_look_weight
		look_target = look_target.lerp(skier.predicted_landing_point + up * look_height_offset, landing_weight)
	var desired_forward := global_position.direction_to(look_target)
	_desired_camera_forward = desired_forward

	var reproj := _yaw_dir - up * _yaw_dir.dot(up)
	_yaw_dir = reproj.normalized() if reproj.length_squared() > 0.001 else travel
	var desired_yaw := desired_forward - up * desired_forward.dot(up)
	if desired_yaw.length_squared() > 0.001:
		desired_yaw = desired_yaw.normalized()
		if _yaw_dir.dot(desired_yaw) < -0.999:
			_yaw_dir = desired_yaw
		else:
			var yaw_rate := lerpf(yaw_rate_slow, yaw_rate_fast, clampf(speed / yaw_speed_reference, 0.0, 1.0)) * _profile_yaw_scale
			_yaw_dir = _slerp_direction(_yaw_dir, desired_yaw, 1.0 - exp(-yaw_rate * delta))
	var desired_pitch := atan2(-desired_forward.dot(up), maxf(desired_forward.dot(_yaw_dir), 0.0001))
	_pitch = lerpf(_pitch, desired_pitch, 1.0 - exp(-pitch_rate * delta))
	var bank_target := 0.0
	if skier != null and camera_state in [CameraState.GROUND, CameraState.LANDING]:
		var bank_speed := clampf(speed / maxf(fov_speed_reference, 1.0), 0.0, 1.0)
		bank_target = -skier.edge_amount * bank_speed * deg_to_rad(skier_bank_reference_degrees) * turn_bank_share
		bank_target = clampf(bank_target, -deg_to_rad(turn_bank_limit_degrees), deg_to_rad(turn_bank_limit_degrees))
	_smoothed_bank = lerpf(_smoothed_bank, bank_target, 1.0 - exp(-turn_bank_response * delta))
	var blended_forward := (_yaw_dir * cos(_pitch) - up * sin(_pitch)).normalized()
	var banked_up := Vector3.UP.rotated(blended_forward, _smoothed_bank)
	global_basis = Basis.looking_at(blended_forward, banked_up)

	var fov_target := base_fov + clampf(speed / fov_speed_reference, 0.0, 1.0) * speed_fov_gain + _profile_fov
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-fov_rate * delta))

func _update_camera_state(skier: SkierController, delta: float) -> void:
	if skier == null:
		camera_state = CameraState.GROUND
		return
	if skier.state == SkierController.State.AIR:
		_air_time += delta
	else:
		if _air_time > landing_min_air_time and skier.state == SkierController.State.GROUND:
			_landing_timer = landing_hold_time
		_air_time = 0.0
	if _landing_timer > 0.0:
		_landing_timer -= delta
	match skier.state:
		SkierController.State.AIR:
			camera_state = CameraState.AIR
		SkierController.State.GRIND:
			camera_state = CameraState.RAIL
		SkierController.State.BAIL:
			camera_state = CameraState.CRASH
		_:
			camera_state = CameraState.LANDING if _landing_timer > 0.0 else CameraState.GROUND

func _air_framing_target(player_position: Vector3, up: Vector3, delta: float) -> Vector3:
	var player_height := player_position.dot(up)
	if not _air_anchor_valid:
		_air_anchor_height = player_height
		_air_anchor_valid = true
	var height_delta := player_height - _air_anchor_height
	var target_height := player_height
	if absf(height_delta) <= air_vertical_dead_zone:
		target_height = _air_anchor_height
	else:
		target_height = player_height - signf(height_delta) * air_vertical_dead_zone
	_air_anchor_height = lerpf(_air_anchor_height, target_height, 1.0 - exp(-air_vertical_anchor_response * delta))
	return player_position + up * (_air_anchor_height - player_height)

func _update_profile(skier: SkierController, delta: float) -> void:
	var distance_delta := 0.0
	var height_delta := 0.0
	var fov_delta := 0.0
	var yaw_scale := 1.0
	var look_ahead := 0.0
	var heading_weight := 0.0
	match camera_state:
		CameraState.AIR:
			distance_delta = air_distance_delta
			height_delta = air_height_delta
			fov_delta = air_fov_delta
			yaw_scale = air_yaw_scale
			look_ahead = air_look_ahead
		CameraState.LANDING:
			distance_delta = landing_distance_delta
			height_delta = landing_height_delta
			fov_delta = landing_fov_delta
			yaw_scale = landing_yaw_scale
			look_ahead = landing_look_ahead
			heading_weight = landing_heading_weight
		CameraState.RAIL:
			distance_delta = rail_distance_delta
		CameraState.CRASH:
			distance_delta = crash_distance_delta
			height_delta = crash_height_delta
			fov_delta = crash_fov_delta
			yaw_scale = crash_yaw_scale
			look_ahead = crash_look_ahead
		_:
			if skier != null:
				heading_weight = clampf(look_heading_weight_min + look_heading_weight_gain * absf(skier.heading_travel_angle_degrees) / heading_angle_reference, look_heading_weight_min, look_heading_weight_min + look_heading_weight_gain)
	var w := 1.0 - exp(-profile_rate * delta)
	_profile_distance = lerpf(_profile_distance, distance_delta, w)
	_profile_height = lerpf(_profile_height, height_delta, w)
	_profile_fov = lerpf(_profile_fov, fov_delta, w)
	_profile_yaw_scale = lerpf(_profile_yaw_scale, yaw_scale, w)
	_profile_look_ahead = lerpf(_profile_look_ahead, look_ahead, w)
	_smoothed_heading_weight = lerpf(_smoothed_heading_weight, heading_weight, w)

func debug_summary() -> String:
	if target == null:
		return "Cam no target"
	var actual_distance := global_position.distance_to(target.global_position)
	return "Cam %s d %.1f  fov %.0f  look %.1f\nCam pitch %+.1f° bank %+.1f° air %.2f  uperr %.1f°  yawx%.2f hw%.2f" % [
		CameraState.keys()[camera_state], actual_distance, camera.fov, _smoothed_look_ahead,
		rad_to_deg(_pitch), rad_to_deg(_smoothed_bank), _smoothed_air_height, rad_to_deg(_filtered_surface_up.angle_to(Vector3.UP)),
		_profile_yaw_scale, _smoothed_heading_weight]

func debug_snapshot() -> Dictionary:
	var actual_forward := -global_basis.z
	return {
		"state": CameraState.keys()[camera_state],
		"fov": camera.fov if camera != null else base_fov,
		"look_ahead": _smoothed_look_ahead,
		"bank_degrees": rad_to_deg(_smoothed_bank),
		"yaw_scale": _profile_yaw_scale,
		"heading_weight": _smoothed_heading_weight,
		"desired_forward": _desired_camera_forward,
		"actual_forward": actual_forward,
		"desired_yaw_degrees": rad_to_deg(atan2(-_desired_camera_forward.x, -_desired_camera_forward.z)),
		"actual_yaw_degrees": rad_to_deg(atan2(-actual_forward.x, -actual_forward.z)),
		"target_position": target.global_position if target != null else Vector3.ZERO,
		"desired_position": _desired_camera_position,
		"actual_position": global_position,
		"target_distance": global_position.distance_to(target.global_position) if target != null else 0.0,
		"horizontal_velocity": _debug_horizontal_velocity,
		"horizontal_speed": _debug_horizontal_velocity.length(),
		"player_facing": _debug_facing_forward,
		"collision_reframed": _collision_reframed,
		"speed_distance_offset": _smoothed_speed_distance,
	}

func _slerp_direction(from: Vector3, to: Vector3, weight: float) -> Vector3:
	if from.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return to.normalized() if to.length_squared() > 0.0001 else from
	from = from.normalized()
	to = to.normalized()
	if from.dot(to) > 0.9995:
		return from.lerp(to, weight).normalized()
	return from.slerp(to, weight).normalized()

func _avoid_collision(from: Vector3, desired: Vector3, up: Vector3, travel: Vector3) -> Vector3:
	_collision_reframed = false
	var direct := _trace_camera_candidate(from, desired)
	if not bool(direct.hit):
		return direct.position
	_collision_reframed = true
	var right := travel.cross(up).normalized()
	if right.length_squared() < 0.001:
		right = global_basis.x
	var alternatives: Array[Vector3] = [
		desired + up * collision_reframe_lift,
		desired + right * collision_shoulder_offset + up * collision_reframe_lift * 0.45,
		desired - right * collision_shoulder_offset + up * collision_reframe_lift * 0.45,
	]
	var best_position: Vector3 = direct.position
	var best_distance := best_position.distance_to(target.global_position)
	for alternative: Vector3 in alternatives:
		var result := _trace_camera_candidate(from, alternative)
		var candidate_position: Vector3 = result.position
		var candidate_distance := candidate_position.distance_to(target.global_position)
		if not bool(result.hit) and candidate_distance >= minimum_camera_distance:
			return candidate_position
		if candidate_distance > best_distance:
			best_distance = candidate_distance
			best_position = candidate_position
	return best_position

func _trace_camera_candidate(from: Vector3, desired: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, desired, 1 | 4)
	query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "position": desired}
	return {"hit": true, "position": hit.position + hit.normal * collision_clearance}

func _stabilize_camera_position(candidate: Vector3, up: Vector3, travel: Vector3 = Vector3.FORWARD) -> Vector3:
	if target == null:
		return candidate
	if not candidate.is_finite() or not up.is_finite() or up.length_squared() < 0.001:
		return _last_stable_camera_position
	up = up.normalized()
	var target_position := target.global_position
	var offset := candidate - target_position
	var up_offset := offset.dot(up)
	var planar_offset := offset - up * up_offset
	if planar_offset.length_squared() < 0.001:
		planar_offset = -_trajectory_dir.slide(up)
	if planar_offset.length_squared() < 0.001:
		planar_offset = Vector3.BACK
	var safe_up_offset := maxf(up_offset, minimum_camera_up_offset)
	var required_planar_distance := sqrt(maxf(minimum_camera_distance * minimum_camera_distance - safe_up_offset * safe_up_offset, 0.0))
	var safe_planar := planar_offset.normalized() * maxf(planar_offset.length(), required_planar_distance)
	var safe_travel := travel.slide(up).normalized()
	if _collision_reframed and safe_travel.length_squared() > 0.001:
		var behind_distance := safe_planar.dot(-safe_travel)
		if behind_distance < minimum_behind_distance:
			safe_planar += -safe_travel * (minimum_behind_distance - behind_distance)
	if offset.length() < minimum_camera_distance or up_offset < minimum_camera_up_offset or safe_planar != planar_offset:
		candidate = target_position + safe_planar + up * safe_up_offset
	var candidate_offset := candidate - target_position
	if candidate_offset.length() > maximum_camera_distance:
		candidate = target_position + candidate_offset.normalized() * maximum_camera_distance
	if not candidate.is_finite() or candidate.distance_to(target_position) < minimum_camera_distance - 0.001:
		return _last_stable_camera_position
	_last_stable_camera_position = candidate
	return candidate
