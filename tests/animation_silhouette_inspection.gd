extends Node3D

const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const OutputPathGuard := preload("res://util/output_path_guard.gd")
const VisualEvidence := preload("res://tests/visual_evidence.gd")
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
const AUDIT_SEGMENT_DURATION := 1.25
const AUDIT_VIEWS: Array[String] = ["front", "side", "opposite", "three_quarter"]
const AUDIT_VIEW_HEADINGS: Array[float] = [0.0, PI * 0.5, PI, -PI * 0.5]
const AUDIT_STYLE_POSES: Array[int] = [
	TrickController.StylePose.SPREAD_EAGLE,
	TrickController.StylePose.DAFFY,
	TrickController.StylePose.SHIFTY_LEFT,
	TrickController.StylePose.SHIFTY_RIGHT,
]
const AUDIT_GRAB_LIBRARY := preload("res://resources/animation/default_grab_animation_library.tres")

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
var presentation_audit_mode := false
var capture_finished := false
var capture_failed := false
var capture_count := 0
var _finish_started := false
var output_directory := ""
var inspection_rail: MeshInstance3D
var inspection_rail_supports: Array[MeshInstance3D] = []
var _grab_showcase_root_heading := 0.0
var _minimum_inversion_clearance := INF
var _audit_pose_ids: Array[int] = []
var _audit_capture_schedule: Array[Dictionary] = []
var _audit_capture_index := 0
var _audit_samples: Array[Dictionary] = []
var _audit_scenario_ids: Array[String] = []
var _audit_previous_rotations: Dictionary = {}
var _audit_matrix_started := false
var _audit_duration := DURATION
var _audit_rate_label := "unspecified"
var evidence_root := ""
var fixed_fps := 0
var evidence: VisualEvidenceSession
var evidence_finished := false
var visual_preset := "default"
var visual_render_scale := 1.0
var visual_environment := "daytime"
var visual_seed := 0

func _ready() -> void:
	evidence_root = _argument_value("--evidence-root=", "")
	fixed_fps = OutputPathGuard.parse_int_range(_argument_value("--fixed-fps=", _argument_value("--audit-fps=", "0")), 0, 0, 240)
	_build_view()
	presentation_capture = OS.get_cmdline_user_args().has("--capture-character-presentation")
	grab_showcase_mode = OS.get_cmdline_user_args().has("--capture-production-grab-showcase")
	presentation_audit_mode = OS.get_cmdline_user_args().has("--capture-animation-presentation-audit")
	_audit_rate_label = _argument_value("--audit-fps=", "unspecified")
	visual_preset = _argument_value("--visual-preset=", "default")
	visual_render_scale = OutputPathGuard.parse_finite_float(_argument_value("--visual-render-scale=", "1.0"), 1.0, 0.5, 1.5)
	visual_environment = _argument_value("--visual-environment=", "daytime").to_lower()
	var seed_text := _argument_value("--visual-seed=", "0")
	visual_seed = int(seed_text) if seed_text.is_valid_int() else 0
	_audit_pose_ids = _grab_pose_ids()
	if presentation_audit_mode:
		_configure_presentation_audit()
	capture_mode = OS.get_cmdline_user_args().has("--capture-silhouette-showcase") or presentation_capture or grab_showcase_mode or presentation_audit_mode
	if capture_mode and RuntimeEnvironment.is_headless():
		push_error("SILHOUETTE_INSPECTION_FAIL: pixel capture requires a GPU renderer")
		call_deferred("_finish", 1, "SILHOUETTE_INSPECTION_FAIL: pixel capture requires a GPU renderer")
		return
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
		elif presentation_audit_mode:
			capture_path = "res://.godot_user/captures/animation_presentation_audit_%s" % _audit_rate_label
		var evidence_directory := evidence_root if not evidence_root.is_empty() else capture_path
		if not evidence_root.is_empty():
			capture_path = evidence_root.path_join("compat")
		output_directory = ProjectSettings.globalize_path(capture_path)
		DirAccess.make_dir_recursive_absolute(output_directory)
		evidence = VisualEvidence.begin({
			"suite_id": "animation",
			"evidence_root": evidence_directory,
			"fixed_fps": fixed_fps,
			"capture_width": 1280,
			"capture_height": 720,
			"context": {
				"scene": "animation_silhouette_inspection",
				"capture_mode": "presentation_audit" if presentation_audit_mode else "presentation" if presentation_capture else "grab_showcase" if grab_showcase_mode else "silhouette",
				"rate_label": _audit_rate_label,
				"production_skeleton": true,
				"environment": visual_environment,
				"preset": visual_preset,
				"render_scale": visual_render_scale,
				"seed": visual_seed,
			},
		})
		get_viewport().scaling_3d_scale = visual_render_scale
		if not presentation_capture and not grab_showcase_mode and not presentation_audit_mode:
			ClipRecorder.clip_saved.connect(_on_clip_saved)
			ClipRecorder.clip_failed.connect(_on_clip_failed)
			ClipRecorder._start_recording()

func _process(delta: float) -> void:
	if capture_finished:
		return
	elapsed += delta
	var duration := _audit_duration if presentation_audit_mode else GRAB_SHOWCASE_DURATION if grab_showcase_mode else DURATION
	var timeline := minf(elapsed, duration - 0.001)
	if presentation_audit_mode:
		if elapsed < DURATION:
			_apply_timeline(minf(elapsed, DURATION - 0.001), delta)
		else:
			_apply_presentation_audit(elapsed - DURATION, delta)
	elif grab_showcase_mode:
		_apply_grab_showcase(timeline, delta)
	else:
		_apply_timeline(timeline, delta)
	camera_rig.step_manual(delta)
	if presentation_audit_mode and elapsed < DURATION:
		_record_audit_sample("timeline", "production", _timeline_audit_label(elapsed), elapsed)
	var review_times: Array[float] = GRAB_SHOWCASE_REVIEW_TIMES if grab_showcase_mode else REVIEW_TIMES
	if capture_mode and not presentation_audit_mode and review_index < review_times.size() and elapsed >= review_times[review_index]:
		_capture_review_frame(review_index)
		review_index += 1
	# The audit records every timeline frame in JSON. Keep PNG readbacks focused
	# on the fixed pose/view holds so multi-rate evidence remains practical.
	if presentation_audit_mode:
		while _audit_capture_index < _audit_capture_schedule.size() and elapsed >= float(_audit_capture_schedule[_audit_capture_index].time):
			_capture_audit_frame(str(_audit_capture_schedule[_audit_capture_index].label))
			_audit_capture_index += 1
	if presentation_audit_mode and elapsed >= duration:
		var audit_ok := _write_presentation_audit_json()
		if _audit_capture_index < _audit_capture_schedule.size():
			capture_failed = true
			push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: captured %d of %d scheduled frames" % [_audit_capture_index, _audit_capture_schedule.size()])
		_finish(0 if audit_ok and not capture_failed else 1, "ANIMATION_PRESENTATION_AUDIT_CAPTURED: %s" % output_directory)
	elif grab_showcase_mode and elapsed >= duration:
		var grab_ok := capture_count == GRAB_SHOWCASE_REVIEW_TIMES.size() and not capture_failed
		if not grab_ok:
			push_error("SILHOUETTE_INSPECTION_FAIL: captured %d of %d grab showcase frames" % [capture_count, GRAB_SHOWCASE_REVIEW_TIMES.size()])
		_finish(0 if grab_ok else 1, "PRODUCTION_GRAB_SHOWCASE_CAPTURED: %s" % output_directory)
	elif presentation_capture and elapsed >= duration:
		var presentation_ok := capture_count == REVIEW_TIMES.size() and not capture_failed
		if not presentation_ok:
			push_error("SILHOUETTE_INSPECTION_FAIL: captured %d of %d presentation frames" % [capture_count, REVIEW_TIMES.size()])
		_finish(0 if presentation_ok else 1, "CHARACTER_PRESENTATION_CAPTURED: %s" % output_directory)
	elif capture_mode and not presentation_audit_mode and elapsed >= duration and ClipRecorder._recording:
		ClipRecorder._stop_recording()
	if capture_mode and not presentation_capture and not grab_showcase_mode and not presentation_audit_mode and elapsed > duration + 12.0:
		push_error("SILHOUETTE_INSPECTION_FAIL: capture did not finish")
		_finish(1)
	elif not capture_mode and elapsed >= duration:
		elapsed = 0.0
		previous_stage = -1
		rig.trigger(SkierAnimationController.AnimationEvent.RESPAWN)

func _argument_value(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback

func _grab_pose_ids() -> Array[int]:
	var pose_ids: Array[int] = []
	var definitions: Array = AUDIT_GRAB_LIBRARY.get("definitions") as Array
	for definition: Resource in definitions:
		if definition == null:
			continue
		var pose := int(definition.get("pose_id"))
		if pose != TrickController.GrabPose.NONE and not pose_ids.has(pose):
			pose_ids.append(pose)
	pose_ids.sort()
	return pose_ids

func _configure_presentation_audit() -> void:
	var segment_count := _audit_pose_ids.size() * AUDIT_VIEWS.size() + AUDIT_STYLE_POSES.size() * AUDIT_VIEWS.size()
	_audit_duration = DURATION + 0.2 + float(segment_count) * AUDIT_SEGMENT_DURATION
	_audit_capture_schedule.clear()
	for segment: int in segment_count:
		var grab_view_count := _audit_pose_ids.size() * AUDIT_VIEWS.size()
		var label := "segment_%02d" % segment
		if segment < grab_view_count:
			var pose := _audit_pose_ids[segment / AUDIT_VIEWS.size()]
			var view := AUDIT_VIEWS[segment % AUDIT_VIEWS.size()]
			label = "grab_%02d_%s_%s_hold.png" % [pose, TrickController.GRAB_NAMES[pose].to_lower().replace(" ", "_"), view]
		else:
			var style_segment := segment - grab_view_count
			var style := AUDIT_STYLE_POSES[style_segment / AUDIT_VIEWS.size()]
			var style_view := AUDIT_VIEWS[style_segment % AUDIT_VIEWS.size()]
			label = "style_%02d_%s_%s_hold.png" % [style, TrickController.STYLE_NAMES[style].to_lower().replace(" ", "_"), style_view]
		_audit_capture_schedule.append({
			"time": DURATION + 0.2 + float(segment) * AUDIT_SEGMENT_DURATION + 0.70,
			"label": label,
		})

func _apply_presentation_audit(matrix_time: float, delta: float) -> void:
	if not _audit_matrix_started:
		_audit_matrix_started = true
		rig.trigger(SkierAnimationController.AnimationEvent.RESPAWN)
		skier.position = Vector3(0.0, 1.0, -0.2)
		_audit_previous_rotations.clear()
	frame.reset()
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.82
	var segment := clampi(int(maxf(matrix_time - 0.2, 0.0) / AUDIT_SEGMENT_DURATION), 0, _audit_capture_schedule.size() - 1)
	var segment_time := fmod(maxf(matrix_time - 0.2, 0.0), AUDIT_SEGMENT_DURATION)
	var phase_name := "setup"
	if segment_time >= 0.18 and segment_time < 0.45:
		phase_name = "reach"
	elif segment_time < 0.88:
		phase_name = "hold"
	elif segment_time < 1.06:
		phase_name = "release"
	else:
		phase_name = "recovery"
	var phase_progress := clampf(segment_time / AUDIT_SEGMENT_DURATION, 0.0, 1.0)
	var view_index := segment % AUDIT_VIEWS.size()
	var grab_view_count := _audit_pose_ids.size() * AUDIT_VIEWS.size()
	var pose_id := TrickController.GrabPose.NONE
	var style_id := TrickController.StylePose.NONE
	var subject_name := "style"
	if segment < grab_view_count:
		pose_id = _audit_pose_ids[segment / AUDIT_VIEWS.size()]
		subject_name = TrickController.GRAB_NAMES[pose_id]
		frame.grab_pose = pose_id if phase_name == "reach" or phase_name == "hold" else TrickController.GrabPose.NONE
		frame.grab_amount = 1.0 if phase_name == "hold" else smoothstep(0.0, 1.0, clampf((segment_time - 0.18) / 0.27, 0.0, 1.0)) if phase_name == "reach" else 0.0
		frame.grab_input_strength = frame.grab_amount
		frame.grab_hold_time = maxf(0.0, segment_time - 0.45)
		frame.grab_release_time = maxf(0.0, segment_time - 0.88)
		frame.trick_phase = TrickCommand.PresentationPhase.RELEASE if phase_name == "release" else TrickCommand.PresentationPhase.OPEN if phase_name == "recovery" else TrickCommand.PresentationPhase.GRAB
	else:
		var style_segment := segment - grab_view_count
		style_id = AUDIT_STYLE_POSES[style_segment / AUDIT_VIEWS.size()]
		subject_name = TrickController.STYLE_NAMES[style_id]
		frame.style_pose = style_id if phase_name != "release" and phase_name != "recovery" else TrickController.StylePose.NONE
		frame.style_amount = 1.0 if phase_name == "hold" else smoothstep(0.0, 1.0, clampf((segment_time - 0.18) / 0.27, 0.0, 1.0)) if phase_name == "reach" else 0.0
		frame.trick_phase = TrickCommand.PresentationPhase.OPEN if phase_name == "recovery" else TrickCommand.PresentationPhase.GRAB
	_set_air(0.68, 0.42)
	skier.position.y = 1.0
	_grab_showcase_root_heading = lerp_angle(
		_grab_showcase_root_heading,
		AUDIT_VIEW_HEADINGS[view_index],
		1.0 - exp(-8.0 * delta)
	)
	skier.rotation.y = _grab_showcase_root_heading
	frame.ski_forward = -skier.global_basis.z
	frame.ski_up = skier.global_basis.y
	frame.body_up = skier.global_basis.y
	frame.angular_velocity_world = skier.global_basis * frame.angular_velocity
	rig.apply_frame(frame, delta)
	_record_audit_sample(subject_name, AUDIT_VIEWS[view_index], phase_name, DURATION + 0.2 + matrix_time)

func _timeline_audit_label(time: float) -> String:
	for index: int in REVIEW_TIMES.size():
		if time <= REVIEW_TIMES[index] + 0.35:
			return REVIEW_LABELS[index]
	return "runout"

func _record_audit_sample(subject_name: String, view_name: String, phase_name: String, sample_time: float) -> void:
	if rig == null:
		return
	var snapshot := rig.debug_snapshot()
	var attachment := rig.equipment_attachment_snapshot()
	var current_rotations := {
		"torso": snapshot.get("chest_rotation", Vector3.ZERO),
		"left_shoulder": snapshot.get("left_shoulder_rotation", Vector3.ZERO),
		"right_shoulder": snapshot.get("right_shoulder_rotation", Vector3.ZERO),
		"left_knee": snapshot.get("left_knee_rotation", Vector3.ZERO),
		"right_knee": snapshot.get("right_knee_rotation", Vector3.ZERO),
		"head": snapshot.get("head_rotation", Vector3.ZERO),
	}
	var motion: Dictionary = {}
	for key: String in current_rotations:
		var value := current_rotations[key] as Vector3
		var previous := _audit_previous_rotations.get(key, value) as Vector3
		motion["%s_delta" % key] = value.distance_to(previous)
		_audit_previous_rotations[key] = value
	var max_pole_offset := 0.0
	var max_boot_gap := 0.0
	if bool(attachment.get("valid", false)):
		max_pole_offset = maxf(float(attachment.get("left_pole_hand_offset_m", 0.0)), float(attachment.get("right_pole_hand_offset_m", 0.0)))
		max_boot_gap = maxf(float(attachment.get("left_boot_binding_position_error", 0.0)), float(attachment.get("right_boot_binding_position_error", 0.0)))
	var terrain_clearance = null
	if str(snapshot.get("state", "")) in ["GROUND", "GRIND"]:
		terrain_clearance = minf(absf(float(snapshot.get("left_gap", 0.0))), absf(float(snapshot.get("right_gap", 0.0))))
	var finite := true
	for value_key: String in ["grab_reach_error", "grab_contact_weight", "landing_compression", "landing_recovery", "left_boot_binding_position_error", "right_boot_binding_position_error", "left_gap", "right_gap"]:
		if not _audit_value_is_finite(snapshot.get(value_key, 0.0)):
			finite = false
	var sample := {
		"time_s": snappedf(sample_time, 0.001),
		"subject": subject_name,
		"view": view_name,
		"phase": phase_name,
		"pose_owner": str(snapshot.get("pose_owner", "")),
		"state": str(snapshot.get("state", "")),
		"hand_to_target_error_m": float(snapshot.get("grab_reach_error", 0.0)),
		"grab_contact_weight": float(snapshot.get("grab_contact_weight", 0.0)),
		"contact_latched": float(snapshot.get("grab_contact_weight", 0.0)) > 0.2,
		"pole_to_hand_offset_m": max_pole_offset,
		"pole_continuity_ok": max_pole_offset <= 1.6,
		"boot_binding_gap_m": max_boot_gap,
		"torso_motion_delta_rad": float(motion.get("torso_delta", 0.0)),
		"shoulder_motion_delta_rad": maxf(float(motion.get("left_shoulder_delta", 0.0)), float(motion.get("right_shoulder_delta", 0.0))),
		"knee_motion_delta_rad": maxf(float(motion.get("left_knee_delta", 0.0)), float(motion.get("right_knee_delta", 0.0))),
		"head_motion_delta_rad": float(motion.get("head_delta", 0.0)),
		"landing_handoff_timing": {
			"phase": str(snapshot.get("landing_phase", "Idle")),
			"blend": float(snapshot.get("landing_blend", 0.0)),
			"alignment": float(snapshot.get("landing_alignment", 0.0)),
			"anticipation": float(snapshot.get("landing_anticipation", 0.0)),
		},
		"landing_compression": float(snapshot.get("landing_compression", 0.0)),
		"landing_recovery": float(snapshot.get("landing_recovery", 0.0)),
		"minimum_inversion_clearance_m": _minimum_inversion_clearance if is_finite(_minimum_inversion_clearance) else null,
		"terrain_clearance_m": terrain_clearance,
		"production_skeleton": str(snapshot.get("rig_adapter", "")) == "skeleton",
		"finite_transforms": finite,
		"state_transition_valid": float(snapshot.get("transition_progress", 0.0)) >= -0.001 and float(snapshot.get("transition_progress", 0.0)) <= 1.001,
	}
	_audit_samples.append(sample)
	if evidence != null:
		evidence.record_sample("animation.audit.timeline", sample)

func _audit_value_is_finite(value) -> bool:
	if value is Vector3:
		return (value as Vector3).is_finite()
	if value is float or value is int:
		return is_finite(float(value))
	return true

func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _timeline_scenario_id(label: String) -> String:
	var normalized := label.to_lower().replace(" ", "_")
	if grab_showcase_mode:
		return "animation.showcase.%s" % normalized
	return "animation.timeline.%s" % normalized

func _audit_scenario_id(label: String) -> String:
	var parts := label.get_basename().split("_")
	if parts.size() >= 3:
		var kind := "grab" if parts[0] == "grab" else "style"
		var pose_id := parts[1]
		return "animation.audit.%s.%s.%s" % [kind, pose_id, _audit_view_name(label)]
	return "animation.audit.%s" % label.get_basename().to_lower()

func _audit_view_name(label: String) -> String:
	var parts := label.get_basename().split("_")
	return parts[parts.size() - 2] if parts.size() >= 2 else "unknown"

func _timeline_state(label: String) -> String:
	if label in ["ground", "carve", "scrape", "switch", "runout"]:
		return "GROUND"
	if label in ["rail_50_50", "rail_slide"]:
		return "GRIND"
	return "AIR"

func _timeline_phase(label: String) -> String:
	if label in ["ground", "runout"]:
		return "ground"
	if label in ["carve", "scrape", "switch"]:
		return label
	if label in ["rail_50_50", "rail_slide"]:
		return "rail"
	if label in ["landing_setup", "landing_impact"]:
		return "landing"
	if label in ["spread_eagle", "daffy", "shifty"]:
		return "style"
	return "air"

func _capture_audit_frame(label: String) -> bool:
	if RuntimeEnvironment.is_headless():
		capture_failed = true
		push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: pixel capture requires a GPU renderer")
		return false
	RenderingServer.force_draw(true)
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		capture_failed = true
		push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: viewport texture was unavailable for %s" % label)
		return false
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		capture_failed = true
		push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: viewport image was empty for %s" % label)
		return false
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	if evidence != null:
		var scenario_id := _audit_scenario_id(label)
		var audit_artifact := evidence.capture_image(scenario_id, "raw", image, {
			"artifact_filename": label,
			"frame_index": _audit_capture_index,
			"time_s": snappedf(float(_audit_capture_schedule[_audit_capture_index].time) if _audit_capture_index < _audit_capture_schedule.size() else elapsed, 0.001),
			"state": "AIR",
			"phase": "hold",
			"view": _audit_view_name(label),
		})
		if audit_artifact.is_empty():
			capture_failed = true
			push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: evidence artifact could not be written for %s" % label)
			return false
		if not _audit_scenario_ids.has(scenario_id):
			_audit_scenario_ids.append(scenario_id)
	else:
		var error := image.save_png(output_directory.path_join(label))
		if error != OK:
			capture_failed = true
			push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: could not save %s (%s)" % [label, error_string(error)])
			return false
	capture_count += 1
	return true

func _write_presentation_audit_json() -> bool:
	var payload := {
		"format": "animation_presentation_audit_v1",
		"rate_hint": _audit_rate_label,
		"duration_s": _audit_duration,
		"supported_grabs": _audit_pose_ids,
		"supported_styles": AUDIT_STYLE_POSES,
		"views": AUDIT_VIEWS,
		"capture_count": _audit_capture_schedule.size(),
		"samples": _audit_samples,
	}
	var path := output_directory.path_join("animation_presentation_audit.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: could not open %s" % path)
		capture_failed = true
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	if evidence != null:
		var timeline_path := evidence.write_json_artifact("animation.audit.timeline", "timeline", "animation_presentation_audit.json", payload, {
			"rate_label": _audit_rate_label,
			"sample_count": _audit_samples.size(),
		})
		if timeline_path.is_empty():
			capture_failed = true
			push_error("ANIMATION_PRESENTATION_AUDIT_FAIL: evidence timeline artifact could not be written")
			return false
		# The trace is emitted once per audit-rate run, but every captured pose
		# references it so catalog role validation remains scenario-local.
		for scenario_id: String in _audit_scenario_ids:
			evidence.register_file_artifact(scenario_id, "timeline", timeline_path, {
				"shared_scenario_id": "animation.audit.timeline",
				"rate_label": _audit_rate_label,
			})
	return true

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

func _capture_review_frame(index: int) -> bool:
	if RuntimeEnvironment.is_headless():
		capture_failed = true
		push_error("SILHOUETTE_INSPECTION_FAIL: pixel capture requires a GPU renderer")
		return false
	RenderingServer.force_draw(true)
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		capture_failed = true
		push_error("SILHOUETTE_INSPECTION_FAIL: viewport texture was unavailable for review frame %d" % (index + 1))
		return false
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		capture_failed = true
		push_error("SILHOUETTE_INSPECTION_FAIL: viewport image was empty for review frame %d" % (index + 1))
		return false
	image.resize(1280, 720, Image.INTERPOLATE_BILINEAR)
	var label: String = GRAB_SHOWCASE_REVIEW_LABELS[index] if grab_showcase_mode else REVIEW_LABELS[index] if index < REVIEW_LABELS.size() else "pose"
	var filename := "audit_timeline_%02d_%s.png" % [index + 1, label] if presentation_audit_mode else "character_%02d_%s.png" % [index + 1, label] if presentation_capture else "grab_%02d_%s.png" % [index + 1, label] if grab_showcase_mode else "silhouette_%02d.png" % (index + 1)
	if evidence != null:
		var scenario_id := _timeline_scenario_id(label)
		var sample_time := REVIEW_TIMES[index] if not grab_showcase_mode and index < REVIEW_TIMES.size() else GRAB_SHOWCASE_REVIEW_TIMES[index] if grab_showcase_mode and index < GRAB_SHOWCASE_REVIEW_TIMES.size() else elapsed
		var review_artifact := evidence.capture_image(scenario_id, "raw", image, {
			"artifact_filename": filename,
			"frame_index": index,
			"time_s": sample_time,
			"state": _timeline_state(label),
			"phase": _timeline_phase(label),
			"view": "three_quarter",
		})
		if review_artifact.is_empty():
			capture_failed = true
			push_error("SILHOUETTE_INSPECTION_FAIL: evidence artifact could not be written for %s" % filename)
			return false
		evidence.record_sample(scenario_id, {
			"time_s": sample_time,
			"frame_index": index,
			"state": _timeline_state(label),
			"phase": _timeline_phase(label),
			"view": "three_quarter",
			"root_position_m": _vector3_array(skier.global_position) if skier != null else [0.0, 0.0, 0.0],
			"root_rotation_rad": _vector3_array(skier.global_rotation) if skier != null else [0.0, 0.0, 0.0],
			"production_skeleton": rig != null,
			"finite_transforms": skier != null and skier.global_position.is_finite() and skier.global_rotation.is_finite(),
		})
	else:
		var error := image.save_png(output_directory.path_join(filename))
		if error != OK:
			capture_failed = true
			push_error("SILHOUETTE_INSPECTION_FAIL: could not save %s (%s)" % [filename, error_string(error)])
			return false
	capture_count += 1
	return true

func _on_clip_saved(path: String) -> void:
	var destination := output_directory.path_join("character_presentation.mp4" if presentation_capture else "animation_silhouette_comparison.mp4")
	var error := DirAccess.copy_absolute(path, destination)
	if error != OK:
		push_error("SILHOUETTE_INSPECTION_FAIL: could not copy clip (%s)" % error_string(error))
		_finish(1)
		return
	if evidence != null:
		evidence.register_file_artifact("animation.timeline", "video", destination, {
			"capture_mode": "presentation" if presentation_capture else "silhouette",
		})
	if not grab_showcase_mode:
		print("SILHOUETTE_INVERSION_CLEARANCE: %.3fm" % _minimum_inversion_clearance)
		if _minimum_inversion_clearance < 0.0:
			push_error("SILHOUETTE_INSPECTION_FAIL: inversion fixture intersects the snow")
			_finish(1)
			return
	print("SILHOUETTE_INSPECTION_CAPTURED: %s" % destination)
	_finish(0)

func _on_clip_failed(reason: String) -> void:
	push_error("SILHOUETTE_INSPECTION_FAIL: " + reason)
	_finish(1)

func _finish(exit_code: int, success_message: String = "") -> void:
	if _finish_started:
		return
	_finish_started = true
	capture_finished = true
	set_process(false)
	if evidence != null and not evidence_finished:
		evidence_finished = true
		evidence.record_check("animation.capture.completed", "capture", "pass" if exit_code == 0 else "fail", capture_count, REVIEW_TIMES.size() if presentation_capture else GRAB_SHOWCASE_REVIEW_TIMES.size() if grab_showcase_mode else _audit_capture_schedule.size(), "Capture process completed")
		evidence.record_check("animation.inversion.clearance", "semantic", "pass" if _minimum_inversion_clearance >= 0.0 else "fail", _minimum_inversion_clearance if is_finite(_minimum_inversion_clearance) else null, 0.0, "Minimum headwear clearance above inspection snow")
		evidence.finish(exit_code)
	if not success_message.is_empty() and exit_code == 0:
		print(success_message)
	if is_instance_valid(ClipRecorder) and ClipRecorder.has_method("_shutdown_capture_workers"):
		ClipRecorder.call("_shutdown_capture_workers")
	AudioManager.shutdown_audio()
	for child: Node in get_children():
		if is_instance_valid(child):
			child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if not RuntimeEnvironment.is_headless():
		# Let queued visual nodes and recorder textures release after the last
		# rendered frame. Quitting immediately can report stale texture RIDs.
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	get_tree().quit(exit_code)

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
	var close_character_capture := grab_showcase_mode or presentation_audit_mode
	camera_rig.follow_distance = 3.85 if close_character_capture else 3.65
	camera_rig.follow_height = 1.12 if close_character_capture else 1.16
	camera_rig.speed_distance_gain = 0.0
	camera_rig.speed_height_gain = 0.0
	camera_rig.air_distance_delta = 0.0
	camera_rig.air_height_delta = 0.0
	camera_rig.air_height = 0.12 if close_character_capture else 0.18
	camera_rig.base_fov = 58.0 if close_character_capture else 60.0
	camera_rig.speed_fov_gain = 0.0
	camera_rig.look_ahead_min = 1.0 if close_character_capture else 0.8
	camera_rig.look_ahead_max = 6.0 if close_character_capture else 4.0
	camera_rig.look_ahead_gain = 0.12 if close_character_capture else 0.08
	camera_rig.composition_inner_rect = Rect2(0.18, 0.15, 0.64, 0.62) if close_character_capture else Rect2(0.2, 0.15, 0.6, 0.64)
	camera_rig.composition_hard_rect = Rect2(0.05, 0.05, 0.9, 0.9)

func _set_inspection_rail_visible(visible: bool) -> void:
	if inspection_rail != null:
		inspection_rail.visible = visible
	for support: MeshInstance3D in inspection_rail_supports:
		support.visible = visible
