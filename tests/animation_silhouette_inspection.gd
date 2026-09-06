extends Node3D

const DURATION := 22.2
const INVERSION_ROOT_HEIGHT := 1.9
const REVIEW_TIMES: Array[float] = [0.8, 2.0, 3.2, 4.4, 5.6, 6.9, 8.2, 9.5, 10.7, 11.9, 13.1, 14.3, 15.5, 17.4, 18.5, 19.6, 20.8, 21.6]
const REVIEW_LABELS := ["ground", "carve", "scrape", "switch", "takeoff", "spin", "grab", "spread_eagle", "daffy", "shifty", "frontflip", "backflip", "cork", "rail_50_50", "rail_slide", "landing_setup", "landing_impact", "runout"]
const GRAB_SHOWCASE_DURATION := 9.0
const GRAB_SHOWCASE_REVIEW_TIMES: Array[float] = [1.2, 3.0, 4.8, 6.6, 8.4]
const GRAB_SHOWCASE_REVIEW_LABELS := ["mute", "japan", "tail", "nose", "double"]
const GRAB_SHOWCASE_POSES: Array[int] = [
	TrickController.GrabPose.MUTE_LEFT,
	TrickController.GrabPose.JAPAN_LEFT,
	TrickController.GrabPose.TAIL,
	TrickController.GrabPose.NOSE,
	TrickController.GrabPose.DOUBLE,
]

var rig: SkierAnimationController
var skier: SkierController
var camera_rig: SkiCameraController
var frame := SkierAnimationFrame.new()
var elapsed := 0.0
var previous_stage := -1
var review_index := 0
var capture_mode := false
var presentation_capture := false
var grab_showcase_mode := false
var capture_finished := false
var output_directory := ""
var inspection_rail: MeshInstance3D
var inspection_rail_supports: Array[MeshInstance3D] = []
var _grab_showcase_root_heading := 0.0
var _minimum_inversion_clearance := INF

func _ready() -> void:
	_build_view()
	presentation_capture = OS.get_cmdline_user_args().has("--capture-character-presentation")
	grab_showcase_mode = OS.get_cmdline_user_args().has("--capture-production-grab-showcase")
	capture_mode = OS.get_cmdline_user_args().has("--capture-silhouette-showcase") or presentation_capture or grab_showcase_mode
	skier = SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.global_transform = Transform3D.IDENTITY
	if grab_showcase_mode:
		# Start the target in its airborne presentation height before the camera
		# seeds its follow pose; the first captured frame must not be a spawn hop.
		skier.position.y = 1.0
	rig = skier.animation_controller
	camera_rig = SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	_configure_capture_camera()
	camera_rig.set_target(skier)
	if capture_mode:
		var capture_path := "res://.godot_user/captures"
		if presentation_capture:
			capture_path = "res://.godot_user/captures/phase_17_after"
		elif grab_showcase_mode:
			capture_path = "res://.godot_user/captures/production_grab_showcase"
		output_directory = ProjectSettings.globalize_path(capture_path)
		DirAccess.make_dir_recursive_absolute(output_directory)
		if not presentation_capture and not grab_showcase_mode:
			ClipRecorder.clip_saved.connect(_on_clip_saved)
			ClipRecorder.clip_failed.connect(_on_clip_failed)
			ClipRecorder._start_recording()

func _process(delta: float) -> void:
	if capture_finished:
		return
	elapsed += delta
	var duration := GRAB_SHOWCASE_DURATION if grab_showcase_mode else DURATION
	var timeline := minf(elapsed, duration - 0.001)
	if grab_showcase_mode:
		_apply_grab_showcase(timeline, delta)
	else:
		_apply_timeline(timeline, delta)
	camera_rig._physics_process(delta)
	var review_times: Array[float] = GRAB_SHOWCASE_REVIEW_TIMES if grab_showcase_mode else REVIEW_TIMES
	if capture_mode and review_index < review_times.size() and elapsed >= review_times[review_index]:
		_capture_review_frame(review_index)
		review_index += 1
	if grab_showcase_mode and elapsed >= duration:
		capture_finished = true
		print("PRODUCTION_GRAB_SHOWCASE_CAPTURED: %s" % output_directory)
		get_tree().quit(0)
	elif presentation_capture and elapsed >= duration:
		capture_finished = true
		print("CHARACTER_PRESENTATION_CAPTURED: %s" % output_directory)
		get_tree().quit(0)
	elif capture_mode and elapsed >= duration and ClipRecorder._recording:
		ClipRecorder._stop_recording()
	if capture_mode and not presentation_capture and not grab_showcase_mode and elapsed > duration + 12.0:
		push_error("SILHOUETTE_INSPECTION_FAIL: capture did not finish")
		get_tree().quit(1)
	elif not capture_mode and elapsed >= duration:
		elapsed = 0.0
		previous_stage = -1
		rig.trigger(SkierAnimationController.AnimationEvent.RESPAWN)

func _apply_grab_showcase(time: float, delta: float) -> void:
	frame.reset()
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.82
	var segment := clampi(int(time / (GRAB_SHOWCASE_DURATION / float(GRAB_SHOWCASE_POSES.size()))), 0, GRAB_SHOWCASE_POSES.size() - 1)
	var segment_width := GRAB_SHOWCASE_DURATION / float(GRAB_SHOWCASE_POSES.size())
	var segment_time := fmod(time, segment_width)
	_set_air(0.58, 0.24)
	frame.grab_pose = GRAB_SHOWCASE_POSES[segment]
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = maxf(0.0, segment_time - 0.25)
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	# Keep the root at a continuous presentation height and ease between a small
	# set of three-quarter views. Large per-grab yaw teleports made contact hard to
	# inspect and caused the showcase to read as a camera/pose snap.
	skier.position.y = 1.0
	var heading_targets: Array[float] = [0.45, 0.45, -0.65, 0.65, 0.45]
	_grab_showcase_root_heading = lerp_angle(
		_grab_showcase_root_heading,
		heading_targets[segment],
		1.0 - exp(-7.0 * delta)
	)
	skier.rotation.y = _grab_showcase_root_heading
	frame.ski_forward = -skier.global_basis.z
	frame.ski_up = skier.global_basis.y
	frame.body_up = skier.global_basis.y
	frame.angular_velocity_world = skier.global_basis * frame.angular_velocity
	rig.apply_frame(frame, delta)

func _apply_timeline(time: float, delta: float) -> void:
	frame.reset()
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.82
	skier.rotation = Vector3.ZERO
	var stage := 0
	if time < 1.2:
		stage = 0
		_set_ground(0.0)
	elif time < 2.4:
		stage = 1
		_set_ground(-1.0)
	elif time < 3.6:
		stage = 2
		_set_ground(0.45)
		frame.skid = 1.0
		frame.skid_ratio = 0.72
		frame.carve_ratio = 0.42
		frame.heading_velocity_delta = 0.52
	elif time < 4.8:
		stage = 3
		_set_ground(0.0)
		frame.switch_stance = true
	elif time < 6.0:
		stage = 4
		var takeoff_progress := clampf((time - 4.8) / 0.32, 0.0, 1.0)
		if takeoff_progress < 1.0:
			_set_ground(0.0)
			frame.compression = lerpf(0.15, 0.95, takeoff_progress)
			frame.trick_phase = TrickCommand.PresentationPhase.SETUP
			frame.gesture_direction = Vector2(1.0, 0.0)
			frame.gesture_strength = 0.82
		else:
			_set_air(time - 5.12, 0.55)
			frame.air_upward_velocity = maxf(0.0, 4.2 - (time - 5.12) * 4.8)
	elif time < 7.8:
		stage = 5
		var spin_progress := (time - 6.0) / 1.8
		_set_air(0.45 + spin_progress * 0.35, 0.48)
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.SPIN_RIGHT
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		frame.angular_velocity = Vector3(0.0, PI, 0.0)
		frame.rotation_accumulated = Vector3(0.0, spin_progress * TAU, 0.0)
		skier.rotation.y = spin_progress * TAU
	elif time < 9.0:
		stage = 6
		_set_air(0.55, 0.44)
		frame.grab_pose = TrickController.GrabPose.MUTE_LEFT
		frame.grab_amount = 1.0
		frame.grab_input_strength = 1.0
		frame.grab_hold_time = time - 7.8
		frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	elif time < 10.2:
		stage = 7
		_set_air(0.56, 0.42)
		frame.style_pose = TrickController.StylePose.SPREAD_EAGLE
		frame.style_amount = 1.0
	elif time < 11.4:
		stage = 8
		_set_air(0.58, 0.4)
		frame.style_pose = TrickController.StylePose.DAFFY
		frame.style_amount = 1.0
	elif time < 12.6:
		stage = 9
		_set_air(0.58, 0.4)
		frame.style_pose = TrickController.StylePose.SHIFTY_LEFT
		frame.style_amount = 1.0
	elif time < 13.8:
		stage = 10
		var front_progress := (time - 12.6) / 1.2
		_set_air(0.55, 0.5)
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.FRONTFLIP
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		frame.angular_velocity.x = 4.8
		frame.rotation_accumulated.x = front_progress * TAU
		skier.rotation.x = front_progress * TAU
	elif time < 15.0:
		stage = 11
		var back_progress := (time - 13.8) / 1.2
		_set_air(0.55, 0.5)
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.BACKFLIP
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		frame.angular_velocity.x = -4.8
		frame.rotation_accumulated.x = -back_progress * TAU
		skier.rotation.x = -back_progress * TAU
	elif time < 16.8:
		stage = 12
		var cork_progress := clampf((time - 15.0) / 1.2, 0.0, 1.0)
		_set_air(0.55 + maxf(time - 16.2, 0.0), maxf(16.8 - time, 0.02))
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.CORK_RIGHT
		frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
		# Return upright through one tilted-axis turn. The telemetry is the
		# derivative of that motion, including its deceleration into contact.
		var cork_axis := Vector3(0.0, 0.65, 0.76).normalized()
		var cork_angle := TAU * smoothstep(0.0, 1.0, cork_progress)
		frame.angular_velocity = cork_axis * TAU * 6.0 * cork_progress * (1.0 - cork_progress) / 1.2
		frame.rotation_accumulated = cork_axis * cork_angle
		frame.rotation_compactness = sin(cork_progress * PI) * 0.85
		skier.basis = Basis(Quaternion(cork_axis, cork_angle))
		if cork_progress > 0.82:
			frame.trick_phase = TrickCommand.PresentationPhase.OPEN
	elif time < 17.9:
		stage = 13
		_set_grind(0)
	elif time < 19.0:
		stage = 14
		_set_grind(1)
	elif time < 20.6:
		stage = 15
		var landing_progress := (time - 19.0) / 1.6
		_set_air(0.62 + landing_progress * 0.3, lerpf(0.36, 0.02, landing_progress))
		frame.predicted_landing_valid = true
		frame.predicted_landing_normal = Vector3(0.0, 0.98, 0.2).normalized()
		frame.trick_phase = TrickCommand.PresentationPhase.LANDING
		# Intentional over-rotated 360 -> corrected toward 180. The root still
		# owns the actual rotation; this only supplies the presentation inputs
		# used to compare projected heading and remaining maneuver residual.
		var correction_progress := smoothstep(0.0, 1.0, landing_progress)
		var corrected_rotation := lerpf(TAU, PI, correction_progress)
		frame.trick_active = true
		frame.trick_intent = true
		frame.trick_kind = TrickCommand.Kind.SPIN_RIGHT
		frame.angular_velocity = Vector3(0.0, lerpf(-2.6, -0.25, correction_progress), 0.0)
		frame.angular_velocity_world = skier.global_basis * frame.angular_velocity
		frame.rotation_accumulated = Vector3(0.0, corrected_rotation, 0.0)
		frame.rotation_residual = Vector3(0.0, lerpf(PI * 0.85, 0.0, correction_progress), 0.0)
		frame.skier_heading = Vector3.FORWARD.rotated(Vector3.UP, corrected_rotation)
		frame.velocity_heading = Vector3.FORWARD
		skier.rotation.y = corrected_rotation
	else:
		stage = 16
		_set_ground(0.0)
		frame.landing_event_active = time < 21.25
		frame.landing_impact_severity = 0.22
		frame.landing_air_time = 0.9
		frame.landing_outcome = LandingSolver.Outcome.CLEAN
	_apply_inspection_root_motion(time)
	if stage != previous_stage:
		if stage == 16:
			rig.trigger(SkierAnimationController.AnimationEvent.LAND_CLEAN, 0.22, 0.0)
		previous_stage = stage
	if time >= 5.12 and time - delta < 5.12:
		rig.trigger(SkierAnimationController.AnimationEvent.POP, 0.9, 0.0)
	# Keep synthetic telemetry honest: these are the gameplay root's ski/body axes,
	# not the visual rig's blended pose.
	frame.ski_forward = -skier.global_basis.z
	frame.ski_up = skier.global_basis.y
	frame.body_up = skier.global_basis.y
	frame.angular_velocity_world = skier.global_basis * frame.angular_velocity
	rig.apply_frame(frame, delta)
	if frame.trick_kind in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP, TrickCommand.Kind.CORK_RIGHT]:
		var production := rig.rig_adapter as SkeletonSkierRig
		var head_position := (production.landmarks().head as Vector3) if production != null else rig.head.global_position
		# Snow is at -0.25m; reserve 0.14m around the head landmark for headwear.
		_minimum_inversion_clearance = minf(_minimum_inversion_clearance, head_position.y + 0.25 - 0.14)

func _set_ground(carve: float) -> void:
	_set_inspection_rail_visible(false)
	skier.state = SkierController.State.GROUND
	skier.velocity = Vector3(0.0, -1.5, -18.0)
	frame.locomotion_state = 0
	frame.grounded = true
	frame.contact_confidence = 1.0
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	frame.edge = carve
	frame.turn_input = carve
	frame.turn_rate = -carve * 0.9
	frame.lateral_acceleration = -carve * 11.0
	frame.carve_ratio = 1.0
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true
	frame.left_ski_target_world = _inspection_ski_contact_transform(Vector3(-0.27, -0.25, -0.11), Vector3.FORWARD)
	frame.right_ski_target_world = _inspection_ski_contact_transform(Vector3(0.27, -0.25, -0.11), Vector3.FORWARD)

func _set_air(air_time: float, landing_time: float) -> void:
	_set_inspection_rail_visible(false)
	skier.state = SkierController.State.AIR
	skier.velocity = Vector3(0.0, -1.0, -18.0)
	frame.locomotion_state = 1
	frame.grounded = false
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.9
	frame.takeoff_upward_speed = 4.0
	frame.air_time = air_time
	frame.air_upward_velocity = lerpf(1.4, -2.8, clampf(air_time, 0.0, 1.0))
	frame.predicted_landing_time = landing_time

func _set_grind(pose: int) -> void:
	_set_inspection_rail_visible(true)
	skier.state = SkierController.State.GRIND
	skier.velocity = Vector3(0.0, 0.0, -13.0)
	frame.locomotion_state = 2
	frame.speed_mps = 13.0
	frame.speed_ratio = 0.55
	frame.rail_speed = 13.0
	frame.rail_pose = pose
	frame.rail_distance_to_end = 5.0
	# Mirror the production controller's rail-owned ski targets. Without these
	# transforms the deterministic fixture exercised only the torso rail layer,
	# leaving a nominal 50-50 pose with skis still perpendicular to the rail.
	frame.rail_direction = Vector3(0.0, 0.0, -1.0)
	frame.rail_up = Vector3.UP
	frame.rail_contact_valid = true
	frame.rail_contact_point = Vector3(0.0, -0.08, -0.75)
	frame.rail_slope = 0.0
	frame.rail_entry_direction = frame.rail_direction
	frame.rail_exit_direction = frame.rail_direction
	var ski_forward_target := frame.rail_direction
	if pose != 0:
		ski_forward_target = ski_forward_target.rotated(Vector3.UP, signf(float(pose)) * PI * 0.5)
	var lateral := ski_forward_target.cross(Vector3.UP).normalized()
	frame.left_ski_target_world = _inspection_ski_contact_transform(
		frame.rail_contact_point - lateral * 0.2,
		ski_forward_target
	)
	frame.right_ski_target_world = _inspection_ski_contact_transform(
		frame.rail_contact_point + lateral * 0.2,
		ski_forward_target
	)
	frame.left_ski_target_valid = true
	frame.right_ski_target_valid = true

func _inspection_ski_contact_transform(contact_point: Vector3, forward: Vector3) -> Transform3D:
	var basis := Basis.looking_at(forward.normalized(), Vector3.UP).orthonormalized()
	return Transform3D(basis, contact_point + Vector3.UP * 0.04)

func _apply_inspection_root_motion(time: float) -> void:
	# The showcase is synthetic, but its root still needs a physically legible
	# path. Keep the authored state changes while replacing the old per-state
	# height teleports with continuous takeoff, rail entry, and landing motion.
	var root_height := 0.0
	if time < 5.12:
		root_height = 0.0
	elif time < 6.0:
		var takeoff_progress := smoothstep(0.0, 1.0, (time - 5.12) / 0.88)
		root_height = lerpf(0.0, INVERSION_ROOT_HEIGHT, takeoff_progress)
	elif time < 16.8:
		# Full inversions need room beneath the root. The old 1.05m fixture
		# intersected the snow with the helmet and descended during the cork.
		# Finish the turn before the separate 0.6-second rail approach beat.
		var rail_entry_progress := smoothstep(0.0, 1.0, (time - 16.2) / 0.6)
		root_height = lerpf(INVERSION_ROOT_HEIGHT, 0.16, rail_entry_progress)
	elif time < 19.0:
		root_height = 0.16
	elif time < 19.32:
		var rail_exit_progress := smoothstep(0.0, 1.0, (time - 19.0) / 0.32)
		root_height = lerpf(0.16, 0.9, rail_exit_progress)
	elif time < 19.8:
		root_height = 0.9
	elif time < 20.6:
		var landing_progress := smoothstep(0.0, 1.0, (time - 19.8) / 0.8)
		root_height = lerpf(0.9, 0.08, landing_progress)
	else:
		var runout_progress := smoothstep(0.0, 1.0, (time - 20.6) / 0.24)
		root_height = lerpf(0.08, 0.0, runout_progress)
	skier.position.y = root_height

func _capture_review_frame(index: int) -> void:
	RenderingServer.force_draw(true)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	image.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	var label: String = GRAB_SHOWCASE_REVIEW_LABELS[index] if grab_showcase_mode else REVIEW_LABELS[index] if index < REVIEW_LABELS.size() else "pose"
	var filename := "character_%02d_%s.png" % [index + 1, label] if presentation_capture else "grab_%02d_%s.png" % [index + 1, label] if grab_showcase_mode else "silhouette_%02d.png" % (index + 1)
	image.save_png(output_directory.path_join(filename))

func _on_clip_saved(path: String) -> void:
	var destination := output_directory.path_join("character_presentation.mp4" if presentation_capture else "animation_silhouette_comparison.mp4")
	var error := DirAccess.copy_absolute(path, destination)
	if error != OK:
		push_error("SILHOUETTE_INSPECTION_FAIL: could not copy clip (%s)" % error_string(error))
		get_tree().quit(1)
		return
	capture_finished = true
	if not grab_showcase_mode:
		print("SILHOUETTE_INVERSION_CLEARANCE: %.3fm" % _minimum_inversion_clearance)
		if _minimum_inversion_clearance < 0.0:
			push_error("SILHOUETTE_INSPECTION_FAIL: inversion fixture intersects the snow")
			get_tree().quit(1)
			return
	print("SILHOUETTE_INSPECTION_CAPTURED: %s" % destination)
	get_tree().quit(0)

func _on_clip_failed(reason: String) -> void:
	push_error("SILHOUETTE_INSPECTION_FAIL: " + reason)
	get_tree().quit(1)

func _build_view() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	add_child(light)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b9d9ec")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	add_child(environment_node)
	var snow := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	snow.mesh = plane
	snow.position.y = -0.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#edf8fc")
	material.roughness = 0.94
	snow.material_override = material
	add_child(snow)
	inspection_rail = MeshInstance3D.new()
	inspection_rail.name = "InspectionRail"
	var rail_mesh := CylinderMesh.new()
	rail_mesh.top_radius = 0.07
	rail_mesh.bottom_radius = 0.07
	rail_mesh.height = 4.0
	rail_mesh.radial_segments = 16
	inspection_rail.mesh = rail_mesh
	inspection_rail.rotation.x = PI * 0.5
	inspection_rail.position = Vector3(0.0, -0.08, -0.75)
	var rail_material := StandardMaterial3D.new()
	rail_material.albedo_color = Color("#385566")
	rail_material.roughness = 0.62
	inspection_rail.material_override = rail_material
	inspection_rail.visible = false
	add_child(inspection_rail)
	for support_z: float in [-1.85, 0.35]:
		var support := MeshInstance3D.new()
		var support_mesh := BoxMesh.new()
		support_mesh.size = Vector3(0.16, 0.48, 0.16)
		support.mesh = support_mesh
		support.position = Vector3(0.0, -0.28, support_z)
		support.material_override = rail_material
		support.visible = false
		add_child(support)
		inspection_rail_supports.append(support)

func _configure_capture_camera() -> void:
	if not capture_mode:
		return
	# Capture-only framing keeps deterministic inspection evidence legible without
	# changing the gameplay camera resource. The regular silhouette timeline uses
	# the same close subject scale as the production grab artifact, while the grab
	# branch retains a little extra distance for hand-to-ski contact.
	camera_rig.follow_distance = 3.85 if grab_showcase_mode else 3.65
	camera_rig.follow_height = 1.12 if grab_showcase_mode else 1.16
	camera_rig.speed_distance_gain = 0.0
	camera_rig.speed_height_gain = 0.0
	camera_rig.air_distance_delta = 0.0
	camera_rig.air_height_delta = 0.0
	camera_rig.air_height = 0.12 if grab_showcase_mode else 0.18
	camera_rig.base_fov = 58.0 if grab_showcase_mode else 60.0
	camera_rig.speed_fov_gain = 0.0
	camera_rig.look_ahead_min = 1.0 if grab_showcase_mode else 0.8
	camera_rig.look_ahead_max = 6.0 if grab_showcase_mode else 4.0
	camera_rig.look_ahead_gain = 0.12 if grab_showcase_mode else 0.08
	camera_rig.composition_inner_rect = Rect2(0.18, 0.15, 0.64, 0.62) if grab_showcase_mode else Rect2(0.2, 0.15, 0.6, 0.64)
	camera_rig.composition_hard_rect = Rect2(0.05, 0.05, 0.9, 0.9)

func _set_inspection_rail_visible(visible: bool) -> void:
	if inspection_rail != null:
		inspection_rail.visible = visible
	for support: MeshInstance3D in inspection_rail_supports:
		support.visible = visible
