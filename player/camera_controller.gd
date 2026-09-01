class_name SkiCameraController
extends Node3D

const CompositionEvaluatorModule := preload("res://player/camera/composition_evaluator.gd")
const CameraFramingSolverModule := preload("res://player/camera/camera_framing_solver.gd")
const CameraCollisionSolverModule := preload("res://player/camera/camera_collision_solver.gd")

## Phase 4 camera: larger skier framing, carve-aware look blending, and
## per-channel smoothing (position/yaw/pitch/FOV/look-ahead/surface-up)
## so terrain suspension stays readable while the camera remains calm.
## State-aware profiles (GROUND/AIR/LANDING/RAIL/CRASH) layer deltas onto
## the speed-scaled base; heading blend is trajectory-only while airborne
## or crashing so spins/flips never wobble the camera.

enum CameraState { GROUND, AIR, LANDING, RAIL, CRASH }

const COMPOSITION_LANDMARK_NAMES := [
	&"head", &"pelvis", &"left_hand", &"right_hand",
	&"left_knee", &"right_knee", &"left_boot", &"right_boot",
	&"left_ski_nose", &"right_ski_nose", &"left_ski_tail", &"right_ski_tail",
]

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
@export var air_vertical_recovery_zone := 1.15
@export var air_vertical_anchor_response := 3.4
@export var air_vertical_edge_response := 9.0
@export var air_vertical_hard_recovery_response := 20.0

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
@export var hockey_divergence_threshold_degrees := 18.0
@export var maximum_camera_yaw_rate_degrees := 90.0

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
@export var maximum_distance_change_rate := 2.4
@export var camera_collision_radius := 0.22
@export var crash_target_height := 0.62
@export var surface_clearance := 0.12

@export_group("Screen Composition")
@export var composition_inner_rect := Rect2(0.30, 0.24, 0.40, 0.36)
@export var composition_hard_rect := Rect2(0.10, 0.08, 0.80, 0.80)
@export var composition_landing_rect := Rect2(0.14, 0.46, 0.72, 0.36)
@export var composition_screen_padding := Vector2(0.015, 0.02)
@export var composition_recovery_response := 12.0
@export var composition_hard_recovery_response := 24.0
@export var composition_shoulder_offset := 2.6
@export var maximum_fov_change_rate := 24.0
@export var maximum_body_occlusion_fraction := 0.25
@export var maximum_landing_occlusion_fraction := 0.40
@export var maximum_relative_correction_speed := 12.0
@export var composition_comfortable_correction_speed := 8.0
@export_range(0.0, 1.0) var landing_visibility_hard_floor := 0.75
@export var landing_visibility_target := 0.95

@export_group("Carve Look")
@export var look_heading_weight_min := 0.15
@export var look_heading_weight_gain := 0.35
@export var heading_angle_reference := 45.0
@export var landing_heading_weight := 0.05
@export var turn_look_ahead_gain := 1.8
@export var carve_look_ahead_gain := 0.08
@export var carve_look_ahead_max := 2.0
@export var carve_look_ahead_rate := 3.5
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

@export_group("Performance")
## Clearance is safety telemetry only; collision-safe placement still runs every
## frame. Sampling it less often avoids six extra rays per camera tick.
@export_range(0.0, 1.0, 0.01) var clearance_telemetry_interval := 1.0 / 30.0
## Five bisection steps keep the landing look correction within about 1/32 of
## its requested weight while avoiding three redundant full composition passes.
@export_range(1, 8, 1) var landing_look_search_iterations := 5

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
var _smoothed_carve_look_ahead_offset := Vector3.ZERO
var _trajectory_dir := Vector3.FORWARD
var _air_time := 0.0
var _landing_timer := 0.0
var _previous_target_position := Vector3.ZERO
var _air_entry_time := -100.0
var _ground_heading_hold_timer := 0.0
var _previous_planar_speed := 0.0
var _profile_distance := 0.0
var _profile_height := 0.0
var _profile_fov := 0.0
var _profile_yaw_scale := 1.0
var _profile_look_ahead := 0.0
var _smoothed_heading_weight := 0.0
var _smoothed_bank := 0.0
var _last_stable_camera_offset := Vector3.ZERO
var _desired_camera_position := Vector3.ZERO
var _composition_recovery_bias := Vector3.ZERO
var _desired_camera_forward := Vector3.FORWARD
var _debug_horizontal_velocity := Vector3.ZERO
var _debug_facing_forward := Vector3.FORWARD
var _collision_reframed := false
var _camera_occluded := false
var _camera_clearance := 1.0
var _camera_fallback_count := 0
var _target_screen_position := Vector2.ZERO
var _last_compositionally_valid_pose := Transform3D.IDENTITY
var _composition_initialized := false
var _composition_valid := false
var _composition_recovery_active := false
var _skier_screen_rect := Rect2()
var _landing_screen_position := Vector2.ZERO
var _landing_look_weight := 0.0
var _foreground_occlusion_fraction := 0.0
var _last_distance_rate := 0.0
var _last_fov_rate := 0.0
var _previous_target_distance := 0.0
var _camera_sphere: SphereShape3D
var _camera_sweep_query: PhysicsShapeQueryParameters3D
var _camera_destination_query: PhysicsShapeQueryParameters3D
var _camera_clearance_query: PhysicsRayQueryParameters3D
var _camera_surface_query: PhysicsRayQueryParameters3D
var _camera_query_exclude: Array[RID] = []
var _clearance_telemetry_timer := 0.0
var _composition_frame_id := 0
var _composition_landmark_frame_id := -1
var _composition_landmark_cache: Array[Vector3] = []
var _composition_evaluation_frame_id := -1
var _composition_evaluation_position := Vector3.ZERO
var _composition_evaluation_basis := Basis.IDENTITY
var _composition_evaluation_fov := 0.0
var _composition_evaluation_up := Vector3.UP
var _composition_evaluation_body_occlusion := true
var _composition_evaluation_landing_occlusion := true
var _composition_evaluation_result := {}
var _composition_start_clear_frame_id := -1
var _composition_start_clear_position := Vector3.ZERO
var _composition_start_clear := true

var _performance_profile_active := false
var _performance_profile_frame_count := 0
var _performance_profile_update_usec := 0
var _performance_profile_max_update_usec := 0
var _performance_profile_state_frames: Array[int] = [0, 0, 0, 0, 0]
var _performance_profile_state_usec: Array[int] = [0, 0, 0, 0, 0]
var _performance_profile_state_max_usec: Array[int] = [0, 0, 0, 0, 0]
var _performance_profile_shape_queries := 0
var _performance_profile_ray_queries := 0
var _performance_profile_composition_evaluations := 0
var _performance_profile_landmark_samples := 0
var _framing_solver := CameraFramingSolverModule.new()
var _collision_solver := CameraCollisionSolverModule.new()

func _ready() -> void:
	_camera_sphere = SphereShape3D.new()
	_camera_sweep_query = PhysicsShapeQueryParameters3D.new()
	_camera_destination_query = PhysicsShapeQueryParameters3D.new()
	_camera_clearance_query = PhysicsRayQueryParameters3D.new()
	_camera_surface_query = PhysicsRayQueryParameters3D.new()
	_framing_solver.configure(
		air_vertical_dead_zone,
		air_vertical_recovery_zone,
		air_vertical_anchor_response,
		air_vertical_edge_response,
		air_vertical_hard_recovery_response
	)
	_configure_camera_queries()
	camera = Camera3D.new()
	camera.current = true
	camera.fov = base_fov
	camera.near = 0.08
	add_child(camera)

func set_target(value: CharacterBody3D) -> void:
	target = value
	_refresh_camera_query_exclude()
	_collision_solver.set_target(target)
	reset_immediate()

func _configure_camera_queries() -> void:
	_camera_sphere.radius = maxf(camera_collision_radius, 0.05)
	_camera_sweep_query.shape = _camera_sphere
	_camera_sweep_query.collision_mask = 1 | 4
	_camera_sweep_query.margin = collision_clearance
	_camera_destination_query.shape = _camera_sphere
	_camera_destination_query.collision_mask = 1 | 4
	_camera_destination_query.margin = collision_clearance
	_camera_clearance_query.collision_mask = 1 | 4
	_camera_surface_query.collision_mask = 1
	_collision_solver.configure(get_world_3d(), target, 1 | 4, camera_collision_radius, collision_clearance)
	_refresh_camera_query_exclude()

func _refresh_camera_query_exclude() -> void:
	_camera_query_exclude.clear()
	if target != null:
		_camera_query_exclude.append(target.get_rid())
	if _camera_sweep_query != null:
		_camera_sweep_query.exclude = _camera_query_exclude
	if _camera_destination_query != null:
		_camera_destination_query.exclude = _camera_query_exclude
	if _camera_clearance_query != null:
		_camera_clearance_query.exclude = _camera_query_exclude
	if _camera_surface_query != null:
		_camera_surface_query.exclude = _camera_query_exclude
	_collision_solver.set_target(target)

func begin_performance_profile() -> void:
	_performance_profile_frame_count = 0
	_performance_profile_update_usec = 0
	_performance_profile_max_update_usec = 0
	_performance_profile_state_frames = [0, 0, 0, 0, 0]
	_performance_profile_state_usec = [0, 0, 0, 0, 0]
	_performance_profile_state_max_usec = [0, 0, 0, 0, 0]
	_performance_profile_shape_queries = 0
	_performance_profile_ray_queries = 0
	_performance_profile_composition_evaluations = 0
	_performance_profile_landmark_samples = 0
	_collision_solver.reset_query_counts()
	_performance_profile_active = true

func end_performance_profile() -> Dictionary:
	_performance_profile_active = false
	return performance_profile_snapshot()

func performance_profile_snapshot() -> Dictionary:
	var state_average_usec: Array[float] = []
	for index: int in range(_performance_profile_state_frames.size()):
		state_average_usec.append(
			float(_performance_profile_state_usec[index]) / float(maxi(_performance_profile_state_frames[index], 1))
		)
	return {
		"frames": _performance_profile_frame_count,
		"average_usec": float(_performance_profile_update_usec) / float(maxi(_performance_profile_frame_count, 1)),
		"max_usec": _performance_profile_max_update_usec,
		"state_frames": _performance_profile_state_frames.duplicate(),
		"state_average_usec": state_average_usec,
		"state_max_usec": _performance_profile_state_max_usec.duplicate(),
		"shape_queries": _performance_profile_shape_queries + _collision_solver.shape_queries,
		"ray_queries": _performance_profile_ray_queries + _collision_solver.ray_queries,
		"composition_evaluations": _performance_profile_composition_evaluations,
		"landmark_samples": _performance_profile_landmark_samples,
	}

func _record_performance_profile_frame(frame_start_usec: int) -> void:
	if not _performance_profile_active or frame_start_usec <= 0:
		return
	var elapsed_usec := maxi(Time.get_ticks_usec() - frame_start_usec, 0)
	var state_index := clampi(camera_state, 0, _performance_profile_state_frames.size() - 1)
	_performance_profile_frame_count += 1
	_performance_profile_update_usec += elapsed_usec
	_performance_profile_max_update_usec = maxi(_performance_profile_max_update_usec, elapsed_usec)
	_performance_profile_state_frames[state_index] += 1
	_performance_profile_state_usec[state_index] += elapsed_usec
	_performance_profile_state_max_usec[state_index] = maxi(_performance_profile_state_max_usec[state_index], elapsed_usec)

func _record_shape_queries(count: int = 1) -> void:
	if _performance_profile_active:
		_performance_profile_shape_queries += count

func _record_ray_queries(count: int = 1) -> void:
	if _performance_profile_active:
		_performance_profile_ray_queries += count

func _record_composition_evaluation() -> void:
	if _performance_profile_active:
		_performance_profile_composition_evaluations += 1

func _record_landmark_samples(count: int) -> void:
	if _performance_profile_active:
		_performance_profile_landmark_samples += count

func reset_immediate() -> void:
	if target == null:
		return
	_composition_frame_id += 1
	_composition_landmark_frame_id = -1
	_composition_landmark_cache.clear()
	_composition_evaluation_frame_id = -1
	_composition_start_clear_frame_id = -1
	_clearance_telemetry_timer = 0.0
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
	_last_stable_camera_offset = global_position - target.global_position
	_desired_camera_position = global_position
	_debug_horizontal_velocity = target.velocity.slide(up)
	_debug_facing_forward = _yaw_dir
	spring_velocity_horizontal = Vector3.ZERO
	spring_velocity_vertical = Vector3.ZERO
	_smoothed_air_height = air_height if (skier != null and skier.state == SkierController.State.AIR) else 0.0
	_air_anchor_height = target.global_position.dot(up)
	_air_anchor_valid = skier != null and skier.state == SkierController.State.AIR
	_framing_solver.reset(_air_anchor_height, _air_anchor_valid)
	_smoothed_speed_distance = clampf(speed * speed_distance_gain, 0.0, speed_distance_cap)
	_smoothed_speed_height = clampf(speed * speed_height_gain, 0.0, speed_height_cap)
	_smoothed_look_ahead = clampf(speed * look_ahead_gain, look_ahead_min, look_ahead_max)
	_smoothed_carve_look_ahead_offset = Vector3.ZERO
	_desired_camera_forward = global_position.direction_to(target.global_position + _yaw_dir * _smoothed_look_ahead + up * look_height_offset)
	var planar := target.velocity.slide(up)
	_trajectory_dir = planar.normalized() if planar.length() > trajectory_heading_speed_threshold else _yaw_dir
	_air_time = 0.0
	_landing_timer = 0.0
	_profile_distance = 0.0
	_profile_height = 0.0
	_profile_fov = 0.0
	_profile_yaw_scale = 1.0
	_profile_look_ahead = 0.0
	_smoothed_heading_weight = 0.0
	_smoothed_bank = 0.0
	_collision_reframed = false
	_composition_recovery_bias = Vector3.ZERO
	_camera_occluded = false
	_camera_clearance = maximum_camera_distance
	_camera_fallback_count = 0
	_composition_valid = false
	_composition_recovery_active = false
	_skier_screen_rect = Rect2()
	_landing_screen_position = Vector2.ZERO
	_landing_look_weight = 0.0
	_foreground_occlusion_fraction = 0.0
	_last_distance_rate = 0.0
	_last_fov_rate = 0.0
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
	_update_profile(skier, 1000.0)
	camera.fov = clampf(
		base_fov + clampf(speed / fov_speed_reference, 0.0, 1.0) * speed_fov_gain + _profile_fov,
		1.0,
		179.0
	)
	look_at(target.global_position + _yaw_dir * _smoothed_look_ahead + up * look_height_offset, Vector3.UP)
	# Seed the fallback only with a pose that satisfies the same composition
	# contract used during the frame loop. An unvalidated reset pose can be
	# rejected later as a fallback, wasting a recovery pass and incrementing the
	# fallback counter on the very first frame.
	_last_compositionally_valid_pose = Transform3D.IDENTITY
	var reset_evaluation := _evaluate_composition(global_position, global_basis, camera.fov, up)
	if _composition_candidate_is_valid(reset_evaluation):
		_last_compositionally_valid_pose = global_transform
	_previous_target_distance = global_position.distance_to(target.global_position)
	_previous_target_position = target.global_position
	_air_entry_time = 0.0 if camera_state == CameraState.AIR else -100.0
	_ground_heading_hold_timer = 0.0
	_previous_planar_speed = target.velocity.slide(_filtered_surface_up).length()
	_composition_initialized = true

func _physics_process(delta: float) -> void:
	if target == null:
		return
	_composition_frame_id += 1
	_composition_start_clear_frame_id = -1
	var profile_frame_start_usec := Time.get_ticks_usec() if _performance_profile_active else 0
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
	# Track AIR entry time for hysteresis grace.
	if camera_state == CameraState.AIR:
		if previous_camera_state != CameraState.AIR:
			_air_entry_time = 0.0
			_framing_solver.reset(target.global_position.dot(up), true)
		else:
			_air_entry_time += delta
	else:
		_air_entry_time = -100.0
		_framing_solver.clear()
	_update_profile(skier, delta)
	if camera_state == CameraState.AIR and previous_camera_state != CameraState.AIR:
		_air_anchor_height = target.global_position.dot(up)
		_air_anchor_valid = true
	elif camera_state != CameraState.AIR:
		_air_anchor_valid = false

	# Feed-forward: camera world motion = player displacement + bounded correction.
	# This lets a 38 m/s skier be followed with ~0 correction instead of fighting a 30 m/s spring.
	var target_position_now := target.global_position
	if _previous_target_position.is_equal_approx(Vector3.ZERO) and target_position_now.length_squared() > 0.01:
		# First valid frame after spawn without reset - avoid huge jump.
		if _previous_target_position.distance_squared_to(target_position_now) > 2500.0:
			_previous_target_position = target_position_now
	var target_displacement := target_position_now - _previous_target_position
	# Respawn/teleport guard: never feed-forward a >25 m jump (reset_immediate handles it).
	if target_displacement.length_squared() > 625.0:
		target_displacement = Vector3.ZERO
		_previous_target_position = target_position_now
	else:
		global_position += target_displacement

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
		# Hockey-stop hold: trigger on strong brake + decel or divergence, not just low absolute speed.
		var deceleration_rate := maxf((_previous_planar_speed - planar_speed) / maxf(delta, 0.0001), 0.0)
		var is_hard_braking := (
			skier != null
			and skier.braking
			and skier.brake_amount > 0.45
			and (
				deceleration_rate > 6.0
				or absf(skier.heading_travel_angle_degrees) > hockey_divergence_threshold_degrees
				or planar_speed < 12.0
			)
		)
		if is_hard_braking:
			_ground_heading_hold_timer = 0.4
			velocity_weight *= 0.15
		elif _ground_heading_hold_timer > 0.0:
			_ground_heading_hold_timer -= delta
			velocity_weight *= 0.35
		var stable_heading_target := _slerp_direction(facing, velocity_heading, velocity_weight)
		# Angular-velocity envelope: cap yaw step to avoid snap on heading flips.
		var desired_angle := _trajectory_dir.angle_to(stable_heading_target) if _trajectory_dir.length_squared() > 0.001 and stable_heading_target.length_squared() > 0.001 else 0.0
		var max_yaw_step := deg_to_rad(90.0) * delta
		var heading_lerp_weight := 1.0 - exp(-ground_heading_response * delta)
		if desired_angle > max_yaw_step and max_yaw_step > 0.0:
			heading_lerp_weight = minf(heading_lerp_weight, max_yaw_step / max(desired_angle, 0.001))
		_trajectory_dir = _slerp_direction(_trajectory_dir, stable_heading_target, heading_lerp_weight)
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
	elif camera_state == CameraState.CRASH:
		# Keep the pelvis/upper body in frame while the skier rotates through a
		# bail; the feet may legitimately disappear into the snow during rest.
		framing_target += up * crash_target_height

	var speed_distance_target := clampf(speed * speed_distance_gain, 0.0, speed_distance_cap)
	var speed_height_target := clampf(speed * speed_height_gain, 0.0, speed_height_cap)
	_smoothed_speed_distance = lerpf(_smoothed_speed_distance, speed_distance_target, 1.0 - exp(-speed_distance_response * delta))
	_smoothed_speed_height = lerpf(_smoothed_speed_height, speed_height_target, 1.0 - exp(-speed_height_response * delta))
	var distance := follow_distance + _smoothed_speed_distance + _profile_distance
	var desired_height := follow_height + _smoothed_speed_height + _smoothed_air_height + _profile_height
	var desired := framing_target - travel * distance + up * desired_height
	_desired_camera_position = desired
	if camera_state in [CameraState.AIR, CameraState.LANDING, CameraState.CRASH]:
		desired += _composition_recovery_bias
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
		# Never blend from the spring destination after it has been rejected by the
		# swept-volume query. The correction-rate clamp below provides smoothing
		# while keeping the committed endpoint collision-safe.
		collision_safe = collision_candidate
	var stabilized := _stabilize_camera_position(collision_safe, up, travel)
	var correction := stabilized - pre_collision_position
	var correction_limit := collision_correction_speed * delta
	if correction.length() > correction_limit and correction_limit > 0.0:
		stabilized = pre_collision_position + correction.normalized() * correction_limit
	var target_position := target.global_position
	var previous_distance := _previous_target_distance if _previous_target_distance > 0.0 else frame_start_position.distance_to(target_position)
	var current_distance := stabilized.distance_to(target_position)
	var distance_rate_limit := maximum_distance_change_rate * delta
	if distance_rate_limit > 0.0 and absf(current_distance - previous_distance) > distance_rate_limit:
		var bounded_distance := previous_distance + clampf(current_distance - previous_distance, -distance_rate_limit, distance_rate_limit)
		var radial := stabilized - target_position
		if radial.length_squared() > 0.001:
			stabilized = target_position + radial.normalized() * bounded_distance
	global_position = _stabilize_camera_position(stabilized, up, travel)
	# Relative correction limit: camera = player displacement + bounded correction.
	var frame_translation := global_position - frame_start_position
	var frame_relative := frame_translation - target_displacement
	var frame_relative_limit := maximum_relative_correction_speed * delta
	if frame_relative.length() > frame_relative_limit and frame_relative_limit > 0.0:
		global_position = frame_start_position + target_displacement + frame_relative.normalized() * frame_relative_limit
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
	var carve_look_ahead_target := Vector3.ZERO
	if skier != null and camera_state in [CameraState.GROUND, CameraState.LANDING] and planar_speed > trajectory_heading_speed_threshold and absf(skier.heading_travel_angle_degrees) > 2.0:
		carve_look_ahead_target = planar.normalized() * clampf(planar_speed * carve_look_ahead_gain, 0.0, carve_look_ahead_max)
	_smoothed_carve_look_ahead_offset = _smoothed_carve_look_ahead_offset.lerp(
		carve_look_ahead_target,
		1.0 - exp(-carve_look_ahead_rate * delta)
	)
	var look_dir := travel
	if skier != null and _smoothed_heading_weight > 0.005:
		var heading := (-target.global_basis.z).slide(up).normalized()
		if heading.length_squared() > 0.05:
			look_dir = _slerp_direction(travel, heading, _smoothed_heading_weight)
	var look_target := framing_target + look_dir * _smoothed_look_ahead + _smoothed_carve_look_ahead_offset + up * look_height_offset
	var landing_weight := 0.0
	if skier != null and camera_state == CameraState.AIR and skier.predicted_landing_valid and skier.velocity.dot(up) < 0.0:
		landing_weight = 1.0 - clampf(skier.predicted_landing_time / 0.75, 0.0, 1.0)
		landing_weight = smoothstep(0.0, 1.0, landing_weight) * predicted_landing_look_weight
		landing_weight = _constrain_landing_look_weight(look_target, skier.predicted_landing_point + up * look_height_offset, landing_weight, up)
		look_target = look_target.lerp(skier.predicted_landing_point + up * look_height_offset, landing_weight)
	_landing_look_weight = landing_weight
	var desired_forward := global_position.direction_to(look_target)
	_desired_camera_forward = desired_forward

	var reproj := _yaw_dir - up * _yaw_dir.dot(up)
	_yaw_dir = reproj.normalized() if reproj.length_squared() > 0.001 else travel
	var desired_yaw := desired_forward - up * desired_forward.dot(up)
	if desired_yaw.length_squared() > 0.001:
		desired_yaw = desired_yaw.normalized()
		var yaw_rate := lerpf(yaw_rate_slow, yaw_rate_fast, clampf(speed / yaw_speed_reference, 0.0, 1.0)) * _profile_yaw_scale
		var yaw_weight := 1.0 - exp(-yaw_rate * delta)
		var desired_angle := _yaw_dir.signed_angle_to(desired_yaw, up)
		var max_yaw_step := deg_to_rad(maximum_camera_yaw_rate_degrees) * delta
		if absf(desired_angle) > max_yaw_step and max_yaw_step > 0.0:
			yaw_weight = minf(yaw_weight, max_yaw_step / maxf(absf(desired_angle), 0.001))
		_yaw_dir = _slerp_direction(_yaw_dir, desired_yaw, yaw_weight)
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
	var fov_before := camera.fov
	var fov_step := (fov_target - fov_before) * (1.0 - exp(-fov_rate * delta))
	var fov_limit := maximum_fov_change_rate * delta
	if fov_limit > 0.0:
		fov_step = clampf(fov_step, -fov_limit, fov_limit)
	camera.fov = clampf(fov_before + fov_step, 1.0, 179.0)
	_last_fov_rate = absf(camera.fov - fov_before) / maxf(delta, 0.0001)

	# Composition owns position only. Orientation stays authoritative in the
	# yaw/pitch controller above so AIR/CRASH recovery cannot bypass the 90 deg/s
	# rendered-yaw envelope with a candidate-basis blend.
	var composition_basis := global_basis
	_apply_screen_composition(frame_start_position, up, travel, look_target, delta)
	global_basis = composition_basis
	var final_position := global_position
	var final_distance := final_position.distance_to(target.global_position)
	var frame_distance := _previous_target_distance if _previous_target_distance > 0.0 else frame_start_position.distance_to(target.global_position)
	var final_distance_limit := maximum_distance_change_rate * delta
	if final_distance_limit > 0.0 and absf(final_distance - frame_distance) > final_distance_limit:
		var bounded_distance := frame_distance + clampf(final_distance - frame_distance, -final_distance_limit, final_distance_limit)
		var final_radial := final_position - target.global_position
		if final_radial.length_squared() > 0.001:
			final_position = target.global_position + final_radial.normalized() * bounded_distance
	var final_translation := final_position - frame_start_position
	var final_relative := final_translation - target_displacement
	var fast_composition_state := camera_state in [CameraState.AIR, CameraState.LANDING, CameraState.CRASH]
	var desired_cap := maximum_relative_correction_speed
	# Soft inner-rect recovery should stay in the comfortable 6-8 m/s band; hard recovery may use full 12.
	# We infer soft when recovery was triggered but hard validity was still passing at frame start.
	if fast_composition_state and _composition_recovery_active:
		var frame_start_eval := _evaluate_composition(frame_start_position, composition_basis, camera.fov, up)
		var is_hard_at_start := not _composition_hard_valid(frame_start_eval)
		if not is_hard_at_start:
			desired_cap = composition_comfortable_correction_speed
	var final_relative_limit := desired_cap * delta
	if final_relative_limit > 0.0 and final_relative.length() > final_relative_limit:
		final_position = frame_start_position + target_displacement + final_relative.normalized() * final_relative_limit
	# Composition recovery is allowed to move quickly, but it must not use that
	# freedom to defeat the independent camera-distance rate limit. Apply the
	# radial limit again after the translation limit, which is the final point at
	# which composition can change the camera position.
	var post_composition_distance := final_position.distance_to(target.global_position)
	if final_distance_limit > 0.0 and absf(post_composition_distance - frame_distance) > final_distance_limit:
		var bounded_post_distance := frame_distance + clampf(
			post_composition_distance - frame_distance,
			-final_distance_limit,
			final_distance_limit
		)
		var post_radial := final_position - target.global_position
		if post_radial.length_squared() > 0.001:
			final_position = target.global_position + post_radial.normalized() * bounded_post_distance
	# Feed-forward hold: respect relative cap even when safety must override.
	# Use frame_start + target_displacement (not raw old world pose) to avoid 1.27 m / 38 m/s jump.
	var feed_forward_hold := frame_start_position + target_displacement
	feed_forward_hold = _stabilize_camera_position(feed_forward_hold, up, travel, false)
	var feed_forward_hold_valid := _fallback_pose_is_valid(feed_forward_hold, frame_start_position, target_displacement, up, delta)
	var emergency_fallback_used := false
	var final_offset := final_position - target.global_position
	if final_offset.length_squared() > 0.001 and final_offset.length() < minimum_camera_distance:
		# A straight interpolation between two valid radial poses can cross the
		# minimum-distance sphere when the heading pivots. Hold the prior valid
		# pose instead of projecting onto the sphere and snapping its direction.
		if feed_forward_hold_valid:
			final_position = feed_forward_hold
		else:
			final_position = frame_start_position
			emergency_fallback_used = true
		final_offset = final_position - target.global_position
	var final_up_offset := final_offset.dot(up)
	if final_up_offset < minimum_camera_up_offset and final_offset.length_squared() > 0.001:
		if final_offset.length() >= minimum_camera_distance:
			# The target can move vertically far enough in one fixed step that the
			# previous camera position falls just below the playable up-offset. Keep
			# the rate-limited radius and rotate the offset onto the minimum-up
			# boundary instead of falling back to a pose whose distance is measured
			# against the new target and therefore pumps the zoom channel.
			var final_planar := final_offset - up * final_up_offset
			if final_planar.length_squared() > 0.001:
				var bounded_planar_length := sqrt(maxf(final_offset.length_squared() - minimum_camera_up_offset * minimum_camera_up_offset, 0.0))
				final_position = target.global_position + final_planar.normalized() * bounded_planar_length + up * minimum_camera_up_offset
			else:
				if feed_forward_hold_valid:
					final_position = feed_forward_hold
				else:
					final_position = frame_start_position
					emergency_fallback_used = true
		else:
			if feed_forward_hold_valid:
				final_position = feed_forward_hold
			else:
				final_position = frame_start_position
				emergency_fallback_used = true
		final_offset = final_position - target.global_position
	# Absolute maximum distance must be enforced after all rate limits and
	# translation clamps. This is the final guard before committing the pose.
	var absolute_distance := final_offset.length()
	if absolute_distance > maximum_camera_distance + 0.001:
		var clamp_dir := final_offset.normalized() if final_offset.length_squared() > 0.001 else -travel
		if clamp_dir.length_squared() < 0.001:
			clamp_dir = Vector3.BACK
		final_position = target.global_position + clamp_dir * maximum_camera_distance
		# Re-check up_offset after max clamp; if violated, fall back.
		var clamped_up := (final_position - target.global_position).dot(up)
		if clamped_up < minimum_camera_up_offset - 0.001:
			if feed_forward_hold_valid:
				final_position = feed_forward_hold
			else:
				final_position = frame_start_position
				emergency_fallback_used = true
	# Ensure the final translation-capped pose is still above the snow surface.
	if get_world_3d() != null:
		_camera_surface_query.from = final_position + up * 8.0
		_camera_surface_query.to = final_position - up * 8.0
		_record_ray_queries()
		var surface_hit := get_world_3d().direct_space_state.intersect_ray(_camera_surface_query)
		if not surface_hit.is_empty() and surface_hit.position is Vector3:
			var surface_height := (surface_hit.position as Vector3).dot(up)
			var cand_height := final_position.dot(up)
			if cand_height < surface_height + surface_clearance:
				if feed_forward_hold_valid:
					final_position = feed_forward_hold
				else:
					final_position = frame_start_position
					emergency_fallback_used = true
	# All radial/translation/surface clamps above can change the swept segment.
	# Revalidate the final segment and destination before committing the pose.
	var final_trace := _trace_camera_candidate(frame_start_position, final_position)
	if bool(final_trace.get("hit", false)) or not _camera_destination_is_clear(final_position):
		var stable_relative_pose := target.global_position + _last_stable_camera_offset
		stable_relative_pose = _stabilize_camera_position(stable_relative_pose, up, travel, false)
		var stable_valid := _fallback_pose_is_valid(stable_relative_pose, frame_start_position, target_displacement, up, delta)
		var trace_position := final_trace.get("position", frame_start_position) as Vector3
		var trace_valid := _fallback_pose_is_valid(trace_position, frame_start_position, target_displacement, up, delta)
		if feed_forward_hold_valid:
			final_position = feed_forward_hold
			emergency_fallback_used = false
		elif stable_valid:
			final_position = stable_relative_pose
			emergency_fallback_used = false
		elif trace_valid:
			final_position = trace_position
			emergency_fallback_used = false
		else:
			# Safety emergency: keeping the old world pose may exceed the relative
			# motion cap, but it is preferable to committing a colliding camera.
			final_position = frame_start_position
			emergency_fallback_used = true
	global_position = final_position
	# Authoritative stable state: only a fully valid, non-emergency committed pose
	# may replace the previous target-relative fallback offset.
	if not emergency_fallback_used and _fallback_pose_is_valid(global_position, frame_start_position, target_displacement, up, delta):
		_last_stable_camera_offset = global_position - target.global_position
	# Composition is position-only, so the rendered basis remains the yaw/pitch
	# controller's bounded orientation in every state.
	global_basis = composition_basis
	_last_distance_rate = absf(global_position.distance_to(target.global_position) - frame_distance) / maxf(delta, 0.0001)
	_previous_target_distance = global_position.distance_to(target.global_position)
	_previous_target_position = target.global_position
	_previous_planar_speed = planar_speed
	_update_composition_telemetry(up, delta)
	_record_performance_profile_frame(profile_frame_start_usec)

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
	return _framing_solver.step_air(player_position, up, delta, _air_entry_time)

func _apply_screen_composition(frame_start_position: Vector3, up: Vector3, travel: Vector3, _look_target: Vector3, delta: float) -> void:
	if target == null or not _composition_initialized or camera == null:
		return
	var base_position := global_position
	var base_evaluation := _evaluate_composition(base_position, global_basis, camera.fov, up)
	var candidates: Array[Vector3] = [base_position]
	var soft_composition_state := camera_state in [CameraState.AIR, CameraState.LANDING, CameraState.CRASH]
	if camera_state in [CameraState.GROUND, CameraState.LANDING, CameraState.RAIL]:
		# Ground follow already has a stable spring, heading, and collision path.
		# Do not orbit around the skier trying to satisfy a transient screen-space
		# bound; that recovery can turn a small framing error into lateral drift.
		_composition_recovery_active = not _composition_hard_valid(base_evaluation)
		_composition_valid = _composition_candidate_is_valid(base_evaluation)
		return
	if _composition_candidate_is_valid(base_evaluation):
		# AIR/CRASH valid base pose satisfies hard framing. Inner violation is a
		# soft preference; recovery is bounded to comfortable speed (8 m/s).
		# Landing visibility is now a quality metric, not validity — never forces recovery.
		var grace_active := _air_entry_time >= 0.0 and _air_entry_time < 0.18
		var inner_violation := float(base_evaluation.get("inner_violation", 0.0))
		var needs_soft := soft_composition_state and inner_violation > 0.0001
		if grace_active and needs_soft:
			# Continuity guarantee: inherit grounded pose for first airborne frames.
			_composition_recovery_active = false
			_composition_valid = true
			return
		if not needs_soft:
			_composition_recovery_active = false
			_composition_valid = true
			return
		# Soft recovery needed and not in grace: generate inner correction below at 8 m/s.
		_composition_recovery_active = true
		_composition_valid = true
		# Fall through to candidate generation for inner correction.
	if not soft_composition_state and _composition_hard_valid(base_evaluation):
		# Preserve the existing ground-camera solution when it already frames the
		# skier. Re-solving every ground frame can turn a heading pivot into a
		# camera teleport.
		_composition_recovery_active = false
		_composition_valid = true
		return
	# Grace: suppress soft inner-rect repositioning for first 0.18 s of AIR.
	# Prevents takeoff snap where GROUND→AIR FOV/distance change would otherwise teleport.
	# Hard invalid (bounds/occlusion) still recovers immediately, but bounded to 12 m/s.
	if soft_composition_state and _air_entry_time >= 0.0 and _air_entry_time < 0.18 and _composition_hard_valid(base_evaluation):
		_composition_recovery_active = false
		_composition_valid = true
		return
	var right := global_basis.x.normalized()
	var camera_up := global_basis.y.normalized()
	var lift := up.normalized() * collision_reframe_lift
	var shoulder := right * composition_shoulder_offset
	var orbit_radius := base_position.distance_to(target.global_position)
	var orbit_right_candidate := base_position + right * (composition_shoulder_offset + 0.8)
	var orbit_left_candidate := base_position - right * (composition_shoulder_offset + 0.8)
	if orbit_radius > 0.001:
		# A lateral carve around the target must not consume the independent
		# camera-distance rate budget. Put the side-step back on the current
		# radius so composition can change azimuth without being flattened by
		# the final zoom limiter.
		orbit_right_candidate = target.global_position + (orbit_right_candidate - target.global_position).normalized() * orbit_radius
		orbit_left_candidate = target.global_position + (orbit_left_candidate - target.global_position).normalized() * orbit_radius
	if soft_composition_state or not _composition_hard_valid(base_evaluation):
		# A foreground feature can occlude the lower ski/boot landmarks even when
		# the camera is already above the skier's head. Include a high clearance
		# candidate so the bounded recovery can climb over a feature instead of
		# repeatedly settling into the same partially occluded pose.
		var foreground_lift := up.normalized() * maxf(collision_reframe_lift * 2.5, collision_reframe_lift + 1.5)
		for offset: Vector3 in [
			camera_up * collision_reframe_lift,
			shoulder,
			-shoulder,
			orbit_right_candidate - base_position,
			orbit_left_candidate - base_position,
			shoulder + camera_up * collision_reframe_lift * 0.45,
			-shoulder + camera_up * collision_reframe_lift * 0.45,
			lift,
			foreground_lift,
			foreground_lift + shoulder,
			foreground_lift - shoulder,
			lift + shoulder,
			lift - shoulder,
		]:
			candidates.append(base_position + offset)

	var inner_correction := _screen_correction_world_offset(base_evaluation, composition_inner_rect, global_basis, camera.fov) if soft_composition_state else Vector3.ZERO
	var hard_correction := _screen_correction_world_offset(base_evaluation, composition_hard_rect, global_basis, camera.fov)
	if inner_correction.length_squared() > 0.0001:
		candidates.append(base_position + inner_correction)
	if hard_correction.length_squared() > 0.0001:
		candidates.append(base_position + hard_correction)

	var best_position := base_position
	var best_evaluation := base_evaluation
	var best_score := INF
	var found_candidate := false
	var best_safe_position := base_position
	var best_safe_evaluation := base_evaluation
	var best_safe_score := INF
	var found_safe_candidate := false
	for raw_candidate: Vector3 in candidates:
		var safe_result := _safe_composition_candidate(base_position, raw_candidate, up, travel)
		if not bool(safe_result.get("valid", false)):
			continue
		var candidate_position := safe_result.position as Vector3
		# Composition is position-only: evaluate every candidate with the already
		# bounded rendered basis instead of inventing a candidate-specific yaw.
		var evaluation := _evaluate_composition(candidate_position, global_basis, camera.fov, up)
		var score := _composition_score(evaluation, candidate_position.distance_to(base_position))
		if not found_safe_candidate or score < best_safe_score:
			found_safe_candidate = true
			best_safe_score = score
			best_safe_position = candidate_position
			best_safe_evaluation = evaluation
		if not _composition_candidate_is_valid(evaluation):
			continue
		if not found_candidate or score < best_score:
			found_candidate = true
			best_score = score
			best_position = candidate_position
			best_evaluation = evaluation

	var base_requires_recovery := not _composition_candidate_is_valid(base_evaluation)
	var base_near_edge := soft_composition_state and float(base_evaluation.get("inner_violation", 0.0)) > 0.0001
	_composition_recovery_active = base_requires_recovery or base_near_edge
	if not found_candidate:
		_camera_fallback_count += 1
		var fallback_position := _last_compositionally_valid_pose.origin
		var fallback_result := _safe_composition_candidate(base_position, fallback_position, up, travel)
		if bool(fallback_result.get("valid", false)):
			var fallback_evaluation := _evaluate_composition(fallback_result.position as Vector3, global_basis, camera.fov, up)
			if _composition_candidate_is_valid(fallback_evaluation):
				best_position = fallback_result.position as Vector3
				best_evaluation = fallback_evaluation
				found_candidate = true
		if not found_candidate and found_safe_candidate:
			# No valid composition was reachable this frame. Use the closest
			# collision-safe correction immediately; the recovery flag and invalid
			# telemetry tell callers that the hard guarantee could not be met.
			best_position = best_safe_position
			best_evaluation = best_safe_evaluation
			found_candidate = true

	if found_candidate:
		if base_requires_recovery and _composition_hard_valid(best_evaluation):
			# Keep the ordinary spring from undoing a hard composition recovery on
			# the next frame. The bias is expressed relative to the uncomposed
			# framing target, so target feed-forward and the existing rate limit
			# continue to own world motion and maximum correction speed.
			_composition_recovery_bias = (best_position - _desired_camera_position).limit_length(maximum_camera_distance)
		elif not base_requires_recovery and _composition_recovery_bias.length_squared() > 0.0001:
			# Once the skier is visible again, return to ordinary framing gradually
			# so the recovery does not create a lateral snap.
			_composition_recovery_bias = _composition_recovery_bias.lerp(
				Vector3.ZERO,
				1.0 - exp(-composition_recovery_response * delta)
			)
		var correction_response := composition_hard_recovery_response if base_requires_recovery else (composition_recovery_response if base_near_edge else 0.0)
		# Bounded correction: hard recovery uses damped motion plus the relative
		# 12 m/s cap applied later. Soft recovery stays in the 8 m/s band.
		var correction_weight := 1.0 - exp(-correction_response * delta)
		var max_soft_step := composition_comfortable_correction_speed * delta
		var max_hard_step := maximum_relative_correction_speed * delta
		var desired_dist := base_position.distance_to(best_position)
		if not base_requires_recovery and max_soft_step > 0.0 and desired_dist > max_soft_step:
			correction_weight = minf(correction_weight, max_soft_step / maxf(desired_dist, 0.001))
		elif base_requires_recovery and max_hard_step > 0.0 and desired_dist > max_hard_step:
			correction_weight = minf(correction_weight, max_hard_step / maxf(desired_dist, 0.001))
		var composed_position := base_position.lerp(best_position, correction_weight)
		var composed_result := _safe_composition_candidate(base_position, composed_position, up, travel)
		if bool(composed_result.get("valid", false)):
			global_position = composed_result.position as Vector3
			best_evaluation = _evaluate_composition(global_position, global_basis, camera.fov, up)

	if _composition_candidate_is_valid(best_evaluation):
		_last_compositionally_valid_pose = global_transform
		_composition_valid = true
	else:
		_composition_valid = false

func _composition_candidate_is_valid(evaluation: Dictionary) -> bool:
	# Landing visibility is a quality preference, not a validity gate.
	# Only hard framing (bounds + occlusion) can invalidate a pose. Landing
	# at 95% is the target, <75% sustained is a warn/fail in tests, but never
	# forces a teleport.
	return _composition_hard_valid(evaluation)

func _safe_composition_candidate(from: Vector3, raw_candidate: Vector3, up: Vector3, travel: Vector3) -> Dictionary:
	if not raw_candidate.is_finite():
		return {"valid": false}
	var start_clear := _composition_start_is_clear(from)
	var trace := _trace_camera_candidate(from, raw_candidate)
	if start_clear and bool(trace.get("hit", false)):
		return {"valid": false}
	var stabilized := _stabilize_camera_position(raw_candidate, up, travel, false)
	if not stabilized.is_finite():
		return {"valid": false}
	# Preserve the candidate's actual offset here. Radially projecting every
	# lift/shoulder solution back to the old radius can put it back through the
	# foreground feature it was selected to clear; the independent distance-rate
	# limiter in _physics_process owns zoom smoothing.
	stabilized = _keep_composition_camera_behind(stabilized, up, travel)
	stabilized = _stabilize_camera_position(stabilized, up, travel, false)
	var post_trace := _trace_camera_candidate(from, stabilized)
	if not _camera_destination_is_clear(stabilized) or (start_clear and bool(post_trace.get("hit", false))):
		return {"valid": false}
	var offset := stabilized - target.global_position
	var up_offset := offset.dot(up.normalized())
	var distance := offset.length()
	if distance < minimum_camera_distance - 0.001 or distance > maximum_camera_distance + 0.001 or up_offset < minimum_camera_up_offset - 0.001:
		return {"valid": false}
	return {"valid": true, "position": stabilized}

func _composition_start_is_clear(position: Vector3) -> bool:
	if _composition_start_clear_frame_id == _composition_frame_id and _composition_start_clear_position.is_equal_approx(position):
		return _composition_start_clear
	_composition_start_clear_frame_id = _composition_frame_id
	_composition_start_clear_position = position
	_composition_start_clear = _camera_destination_is_clear(position)
	return _composition_start_clear

func _camera_destination_is_clear(position: Vector3) -> bool:
	return _collision_solver.destination_is_clear(position)

func _fallback_pose_is_valid(candidate: Vector3, frame_start_position: Vector3, target_displacement: Vector3, up: Vector3, delta: float) -> bool:
	if target == null or not candidate.is_finite():
		return false
	var safe_up := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var offset := candidate - target.global_position
	var distance := offset.length()
	if distance < minimum_camera_distance - 0.001 or distance > maximum_camera_distance + 0.001:
		return false
	if offset.dot(safe_up) < minimum_camera_up_offset - 0.001:
		return false
	var relative := candidate - (frame_start_position + target_displacement)
	var relative_limit := maximum_relative_correction_speed * delta + 0.02
	if relative.length() > relative_limit:
		return false
	if not _camera_destination_is_clear(candidate):
		return false
	var trace := _trace_camera_candidate(frame_start_position, candidate)
	return not bool(trace.get("hit", false))

func _keep_composition_camera_behind(candidate: Vector3, up: Vector3, travel: Vector3) -> Vector3:
	if target == null or camera_state not in [CameraState.AIR, CameraState.LANDING, CameraState.CRASH]:
		return candidate
	var safe_travel := travel.slide(up).normalized()
	if safe_travel.length_squared() < 0.001:
		return candidate
	var target_position := target.global_position
	var offset := candidate - target_position
	var up_offset := offset.dot(up.normalized())
	var planar := offset - up.normalized() * up_offset
	var behind_distance := planar.dot(-safe_travel)
	if behind_distance < minimum_behind_distance:
		planar += -safe_travel * (minimum_behind_distance - behind_distance)
		candidate = target_position + planar + up.normalized() * up_offset
	return candidate

func _evaluate_composition(
	camera_position: Vector3,
	camera_basis: Basis,
	fov: float,
	up: Vector3,
	include_body_occlusion: bool = true,
	include_landing_occlusion: bool = true
) -> Dictionary:
	if (
		_composition_evaluation_frame_id == _composition_frame_id
		and _composition_evaluation_position.is_equal_approx(camera_position)
		and _composition_evaluation_basis.is_equal_approx(camera_basis)
		and is_equal_approx(_composition_evaluation_fov, fov)
		and _composition_evaluation_up.is_equal_approx(up)
		and _composition_evaluation_body_occlusion == include_body_occlusion
		and _composition_evaluation_landing_occlusion == include_landing_occlusion
	):
		return _composition_evaluation_result
	_record_composition_evaluation()
	var landmarks := _composition_landmarks()
	var viewport_size := _composition_viewport_size()
	var bounds := Rect2()
	var bounds_initialized := false
	var average_depth := 0.0
	var depth_count := 0
	var body_occluded := 0
	var behind_count := 0
	for world_position: Vector3 in landmarks:
		var projected := _project_composition_point(camera_position, camera_basis, fov, viewport_size, world_position)
		var depth_val := float(projected.depth)
		if depth_val <= 0.01:
			behind_count += 1
			body_occluded += 1
			continue
		var screen := projected.screen as Vector2
		if not screen.is_finite():
			behind_count += 1
			body_occluded += 1
			continue
		if not bounds_initialized:
			bounds = Rect2(screen, Vector2.ZERO)
			bounds_initialized = true
		else:
			bounds = bounds.expand(screen)
		average_depth += depth_val
		depth_count += 1
		if include_body_occlusion and _is_foreground_occluded(camera_position, world_position):
			body_occluded += 1
	if not bounds_initialized:
		bounds = Rect2(-10.0, -10.0, 20.0, 20.0)
	var depth := average_depth / maxf(float(depth_count), 1.0)
	var body_occlusion := float(body_occluded) / maxf(float(landmarks.size()), 1.0)
	var hard_violation := _rect_violation(bounds, composition_hard_rect)
	var inner_violation := _rect_violation(bounds, composition_inner_rect)
	if behind_count > 0:
		hard_violation = INF
		inner_violation = INF
	var landing_screen := Vector2.ZERO
	var landing_violation := 0.0
	var landing_occlusion := 0.0
	var landing_valid := false
	var skier := target as SkierController
	var descending := skier != null and camera_state == CameraState.AIR and skier.predicted_landing_valid and skier.velocity.dot(up) < 0.0
	if descending:
		var landing_projection := _project_composition_point(camera_position, camera_basis, fov, viewport_size, skier.predicted_landing_point)
		landing_screen = landing_projection.screen as Vector2
		landing_violation = _rect_violation(Rect2(landing_screen, Vector2.ZERO), composition_landing_rect)
		landing_occlusion = 1.0 if include_landing_occlusion and _is_foreground_occluded(camera_position, skier.predicted_landing_point) else 0.0
		landing_valid = landing_violation <= 0.0001 and landing_occlusion <= maximum_landing_occlusion_fraction
	var evaluation := {
		"skier_screen_rect": bounds,
		"landing_screen_position": landing_screen,
		"hard_violation": hard_violation,
		"inner_violation": inner_violation,
		"landing_violation": landing_violation,
		"landing_occlusion": landing_occlusion,
		"landing_valid": landing_valid,
		"body_occlusion": body_occlusion,
		"foreground_occlusion": maxf(body_occlusion, landing_occlusion),
		"average_depth": depth,
	}
	_composition_evaluation_frame_id = _composition_frame_id
	_composition_evaluation_position = camera_position
	_composition_evaluation_basis = camera_basis
	_composition_evaluation_fov = fov
	_composition_evaluation_up = up
	_composition_evaluation_body_occlusion = include_body_occlusion
	_composition_evaluation_landing_occlusion = include_landing_occlusion
	_composition_evaluation_result = evaluation
	return evaluation

func _composition_score(evaluation: Dictionary, movement: float) -> float:
	return CompositionEvaluatorModule.score(evaluation, movement)

func _composition_hard_valid(evaluation: Dictionary) -> bool:
	return CompositionEvaluatorModule.hard_valid(evaluation, maximum_body_occlusion_fraction)

func _screen_correction_world_offset(evaluation: Dictionary, desired_rect: Rect2, camera_basis: Basis, fov: float) -> Vector3:
	return CompositionEvaluatorModule.screen_correction_world_offset(
		evaluation,
		desired_rect,
		camera_basis,
		fov,
		_composition_viewport_size(),
		minimum_camera_distance
	)

func _composition_landmarks() -> Array[Vector3]:
	if _composition_landmark_frame_id == _composition_frame_id:
		return _composition_landmark_cache
	var points: Array[Vector3] = []
	if target != null and target.has_method("animation_debug_landmark"):
		for landmark: StringName in COMPOSITION_LANDMARK_NAMES:
			var value := target.call("animation_debug_landmark", landmark) as Vector3
			if value.is_finite():
				points.append(value)
	if points.size() < 2 and target != null:
		points = [target.global_position, target.global_position + Vector3.UP * 1.8]
	_composition_landmark_cache = points
	_composition_landmark_frame_id = _composition_frame_id
	_record_landmark_samples(points.size())
	return _composition_landmark_cache

func _composition_viewport_size() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	if viewport_size.x > 1.0 and viewport_size.y > 1.0:
		return viewport_size
	# Detached/headless camera rigs still need the project's configured aspect;
	# a fixed 1920x1080 fallback silently skewed screen-space correction on
	# non-16:9 test or accessibility viewports.
	var configured_width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	var configured_height := float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	return Vector2(maxf(configured_width, 1.0), maxf(configured_height, 1.0))

func _project_composition_point(camera_position: Vector3, camera_basis: Basis, fov: float, viewport_size: Vector2, world_position: Vector3) -> Dictionary:
	return CompositionEvaluatorModule.project_point(camera_position, camera_basis, fov, viewport_size, world_position)

func _is_foreground_occluded(camera_position: Vector3, world_position: Vector3) -> bool:
	return _collision_solver.foreground_occluded(camera_position, world_position, surface_clearance)

func _rect_violation(value: Rect2, container: Rect2) -> float:
	return CompositionEvaluatorModule.rect_violation(value, container)

func _constrain_landing_look_weight(base_target: Vector3, landing_target: Vector3, requested_weight: float, up: Vector3) -> float:
	if requested_weight <= 0.0:
		return 0.0
	var low := 0.0
	var high := requested_weight
	var best := 0.0
	# Composition may translate the camera before it evaluates the landing
	# target. Check the current pose and every collision-safe reframe candidate,
	# rather than validating the look rotation at the pre-composition position
	# only. This keeps a valid landing guarantee from becoming optimistic after
	# a shoulder/lift correction moves the camera.
	var candidate_positions: Array[Vector3] = [global_position]
	var camera_right := global_basis.x.normalized()
	var camera_up := global_basis.y.normalized()
	var candidate_offsets: Array[Vector3] = [
		camera_up * collision_reframe_lift,
		camera_right * composition_shoulder_offset + camera_up * collision_reframe_lift * 0.45,
		-camera_right * composition_shoulder_offset + camera_up * collision_reframe_lift * 0.45,
		up.normalized() * collision_reframe_lift,
	]
	for offset: Vector3 in candidate_offsets:
		var safe_result := _safe_composition_candidate(global_position, global_position + offset, up, _trajectory_dir)
		if bool(safe_result.get("valid", false)):
			candidate_positions.append(safe_result.position as Vector3)
	for _index: int in landing_look_search_iterations:
		var weight := (low + high) * 0.5
		var blended_target := base_target.lerp(landing_target, weight)
		var all_candidates_valid := true
		for candidate_position: Vector3 in candidate_positions:
			var basis := _look_basis_for_pose(candidate_position, blended_target, up)
			# Body occlusion is checked by the authoritative composition pass after
			# this look weight is selected. The bisection only needs projected body
			# bounds plus the landing ray, avoiding 12 redundant rays per candidate.
			var evaluation := _evaluate_composition(candidate_position, basis, camera.fov, up, false, true)
			var body_valid := float(evaluation.get("hard_violation", INF)) <= 0.0001
			var landing_valid := weight <= 0.001 or bool(evaluation.get("landing_valid", false))
			if not body_valid or not landing_valid:
				all_candidates_valid = false
				break
		if all_candidates_valid:
			best = weight
			low = weight
		else:
			high = weight
	return best

func _look_basis_for_target(look_target: Vector3, up: Vector3) -> Basis:
	return _look_basis_for_pose(global_position, look_target, up)

func _look_basis_for_pose(camera_position: Vector3, look_target: Vector3, up: Vector3) -> Basis:
	var desired_forward := camera_position.direction_to(look_target)
	if desired_forward.length_squared() < 0.001:
		return global_basis
	var projected_yaw := desired_forward - up * desired_forward.dot(up)
	if projected_yaw.length_squared() < 0.001:
		return global_basis
	projected_yaw = projected_yaw.normalized()
	var desired_pitch := atan2(-desired_forward.dot(up), maxf(desired_forward.dot(projected_yaw), 0.0001))
	var blended_forward := (projected_yaw * cos(desired_pitch) - up * sin(desired_pitch)).normalized()
	var banked_up := Vector3.UP.rotated(blended_forward, _smoothed_bank)
	return Basis.looking_at(blended_forward, banked_up)

func _update_composition_telemetry(up: Vector3, delta: float) -> void:
	var evaluation := _evaluate_composition(global_position, global_basis, camera.fov, up)
	_skier_screen_rect = evaluation.get("skier_screen_rect", Rect2()) as Rect2
	_landing_screen_position = evaluation.get("landing_screen_position", Vector2.ZERO) as Vector2
	_foreground_occlusion_fraction = float(evaluation.get("foreground_occlusion", 0.0))
	_clearance_telemetry_timer -= delta
	if clearance_telemetry_interval <= 0.0 or _clearance_telemetry_timer <= 0.0:
		_camera_clearance = _measure_camera_clearance(global_position)
		_clearance_telemetry_timer = maxf(clearance_telemetry_interval, 0.0)
	_composition_valid = _composition_candidate_is_valid(evaluation)
	_target_screen_position = _skier_screen_rect.get_center()
	if _composition_valid:
		_last_compositionally_valid_pose = global_transform

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
	var effective_rate := profile_rate
	if _air_entry_time >= 0.0 and _air_entry_time < 0.25:
		# Continuity guarantee: do not snap distance/FOV/yaw on GROUND→AIR.
		effective_rate = profile_rate * 0.25
	var w := 1.0 - exp(-effective_rate * delta)
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
	return "Cam %s d %.1f  fov %.0f  look %.1f\nCam pitch %+.1f° bank %+.1f° air %.2f  uperr %.1f°  yawx%.2f hw%.2f\nCam occ %s clear %.2f fallback %d" % [
		CameraState.keys()[camera_state], actual_distance, camera.fov, _smoothed_look_ahead,
		rad_to_deg(_pitch), rad_to_deg(_smoothed_bank), _smoothed_air_height, rad_to_deg(_filtered_surface_up.angle_to(Vector3.UP)),
		_profile_yaw_scale, _smoothed_heading_weight, _camera_occluded, _camera_clearance, _camera_fallback_count]

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
		"camera_occluded": _camera_occluded,
		"camera_clearance": _camera_clearance,
		"camera_fallback_count": _camera_fallback_count,
		"composition_fallback_count": _camera_fallback_count,
		"target_screen_position": _target_screen_position,
		"skier_screen_rect": _skier_screen_rect,
		"landing_screen_position": _landing_screen_position,
		"composition_valid": _composition_valid,
		"composition_recovery_active": _composition_recovery_active,
		"landing_look_weight": _landing_look_weight,
		"foreground_occlusion_fraction": _foreground_occlusion_fraction,
		"distance_rate": _last_distance_rate,
		"fov_rate": _last_fov_rate,
		"speed_distance_offset": _smoothed_speed_distance,
		"carve_look_ahead_offset": _smoothed_carve_look_ahead_offset,
		"hockey_heading_hold_active": _ground_heading_hold_timer > 0.0,
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
		_camera_occluded = false
		return direct.position
	_collision_reframed = true
	_camera_occluded = true
	var right := travel.cross(up).normalized()
	if right.length_squared() < 0.001:
		right = global_basis.x
	var alternatives: Array[Vector3] = [
		desired + up * collision_reframe_lift,
		desired + right * collision_shoulder_offset + up * collision_reframe_lift * 0.45,
		desired - right * collision_shoulder_offset + up * collision_reframe_lift * 0.45,
	]
	for alternative: Vector3 in alternatives:
		var result := _trace_camera_candidate(from, alternative)
		var candidate_position: Vector3 = result.position
		var candidate_distance := candidate_position.distance_to(target.global_position)
		if not bool(result.hit) and candidate_distance >= minimum_camera_distance:
			return candidate_position
	# Every candidate is occluded. Hold the last valid offset-relative pose instead
	# of moving the camera through a feature or snapping into its near side.
	_camera_fallback_count += 1
	if target != null and _last_stable_camera_offset.is_finite():
		return target.global_position + _last_stable_camera_offset
	return direct.position

func _measure_camera_clearance(position: Vector3) -> float:
	return _collision_solver.measure_clearance(position, global_basis, maximum_camera_distance)

func _trace_camera_candidate(from: Vector3, desired: Vector3) -> Dictionary:
	return _collision_solver.trace(from, desired)

func _stabilize_camera_position(candidate: Vector3, up: Vector3, travel: Vector3 = Vector3.FORWARD, _remember_stable: bool = false) -> Vector3:
	if target == null:
		return candidate
	if not candidate.is_finite() or not up.is_finite() or up.length_squared() < 0.001:
		if target != null and _last_stable_camera_offset.is_finite():
			return target.global_position + _last_stable_camera_offset
		return candidate
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
	# A camera-volume sweep keeps features out of the lens; this final vertical
	# probe also prevents a spring overshoot from placing the camera below the
	# snow surface on a steep pitch or during crash recovery.
	_camera_surface_query.from = candidate + up * 8.0
	_camera_surface_query.to = candidate - up * 8.0
	_record_ray_queries()
	var surface_hit := get_world_3d().direct_space_state.intersect_ray(_camera_surface_query)
	if not surface_hit.is_empty() and surface_hit.position is Vector3:
		var surface_height := (surface_hit.position as Vector3).dot(up)
		var candidate_height := candidate.dot(up)
		if candidate_height < surface_height + surface_clearance:
			candidate += up * (surface_height + surface_clearance - candidate_height)
	var candidate_offset := candidate - target_position
	if candidate_offset.length() > maximum_camera_distance:
		candidate = target_position + candidate_offset.normalized() * maximum_camera_distance
	candidate_offset = candidate - target_position
	if not candidate.is_finite() or candidate_offset.length() < minimum_camera_distance - 0.001 or candidate_offset.dot(up) < minimum_camera_up_offset - 0.001:
		if _last_stable_camera_offset.is_finite():
			return target_position + _last_stable_camera_offset
		return candidate
	return candidate
