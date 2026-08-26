class_name SkierAnimationController
extends Node3D

enum AnimationEvent {
	POP,
	LAND_CLEAN,
	LAND_SKETCHY,
	LAND_HARD,
	GRIND_ENTER,
	GRIND_EXIT,
	BAIL,
	RESPAWN,
}

const STATE_GROUND := 0
const STATE_AIR := 1
const STATE_GRIND := 2
const STATE_BAIL := 3

@export var profile: SkierAnimationProfile = preload("res://resources/animation/default_animation_profile.tres")

var balance_root: Node3D
var pelvis: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
var left_hip: Node3D
var right_hip: Node3D
var left_knee: Node3D
var right_knee: Node3D
var left_boot: Node3D
var right_boot: Node3D
var left_ski: Node3D
var right_ski: Node3D
var left_shoulder: Node3D
var right_shoulder: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_hand: Node3D
var right_hand: Node3D
var left_pole: Node3D
var right_pole: Node3D

var _rotation_targets: Dictionary = {}
var _position_targets: Dictionary = {}
var _elapsed := 0.0
var _reaction_event := -1
var _reaction_time := 0.0
var _reaction_duration := 0.0
var _reaction_strength := 0.0
var _reaction_side := 0.0
var _current_state := STATE_AIR
var _current_pose_name := "Air Neutral"
var _current_blend := 0.0
var _layer_weight := 1.0
var _grab_target_world := Vector3.ZERO
var _grab_hand: Node3D

func _ready() -> void:
	_build_articulated_rig()

func apply_frame(frame: SkierAnimationFrame, delta: float) -> void:
	_elapsed += delta
	_current_state = frame.locomotion_state
	_reset_targets()
	match frame.locomotion_state:
		STATE_GROUND: _apply_ground_pose(frame)
		STATE_AIR: _apply_air_pose(frame)
		STATE_GRIND: _apply_grind_pose(frame)
		STATE_BAIL: _apply_bail_pose(frame)
	_apply_trick_layer(frame)
	_apply_reaction(frame, delta)
	_apply_secondary_motion(frame)
	_blend_targets(delta)

func trigger(event: int, strength: float = 1.0, side: float = 0.0) -> void:
	_reaction_event = event
	_reaction_time = 0.0
	_reaction_strength = clampf(strength, 0.0, 1.5)
	_reaction_side = clampf(side, -1.0, 1.0)
	match event:
		AnimationEvent.POP: _reaction_duration = profile.pop_duration
		AnimationEvent.LAND_CLEAN: _reaction_duration = profile.clean_landing_duration
		AnimationEvent.LAND_SKETCHY: _reaction_duration = profile.sketchy_landing_duration
		AnimationEvent.LAND_HARD: _reaction_duration = profile.hard_landing_duration
		AnimationEvent.GRIND_ENTER, AnimationEvent.GRIND_EXIT: _reaction_duration = 0.28
		AnimationEvent.BAIL: _reaction_duration = 1.2
		AnimationEvent.RESPAWN:
			_reaction_duration = 0.0
			_reset_pose_immediately()

func debug_snapshot() -> Dictionary:
	return {
		"state": ["GROUND", "AIR", "GRIND", "BAIL"][_current_state],
		"pose": _current_pose_name,
		"blend": _current_blend,
		"reaction": _reaction_event,
		"reaction_time": _reaction_time,
		"pelvis_height": pelvis.position.y,
		"pelvis_rotation": pelvis.rotation,
		"left_ski_rotation": left_ski.rotation,
		"right_ski_rotation": right_ski.rotation,
		"grab_reach_error": _grab_hand.global_position.distance_to(_grab_target_world) if _grab_hand != null else 0.0,
	}

func _reset_targets() -> void:
	_rotation_targets.clear()
	_position_targets.clear()
	_grab_hand = null
	for joint: Node3D in [
		balance_root, pelvis, spine, chest, head,
		left_hip, right_hip, left_knee, right_knee,
		left_boot, right_boot, left_ski, right_ski,
		left_shoulder, right_shoulder, left_elbow, right_elbow,
		left_hand, right_hand, left_pole, right_pole,
	]:
		_rotation_targets[joint] = Vector3.ZERO
	_position_targets[pelvis] = Vector3(0.0, 0.96, 0.0)
	_position_targets[chest] = Vector3(0.0, 0.42, 0.0)
	_position_targets[left_hip] = Vector3(-0.24, -0.04, 0.0)
	_position_targets[right_hip] = Vector3(0.24, -0.04, 0.0)

func _apply_ground_pose(frame: SkierAnimationFrame) -> void:
	var speed_flex := profile.speed_knee_flex * frame.speed_ratio
	var compression := frame.compression * profile.compression_depth
	var flex := profile.neutral_knee_flex + speed_flex + compression
	var deep_carve := smoothstep(profile.deep_carve_threshold, 1.0, absf(frame.edge))
	var carve_roll := -frame.edge * profile.carve_hip_roll * lerpf(0.55, 1.0, frame.speed_ratio)
	var skid_side := signf(frame.skid) if absf(frame.skid) > 0.05 else signf(frame.edge)
	_current_blend = frame.edge
	_current_pose_name = "Ground Neutral"

	_add_rotation(balance_root, Vector3(0.0, 0.0, carve_roll * 0.32))
	_add_rotation(pelvis, Vector3(-0.08 - frame.tuck * 0.2, 0.0, carve_roll))
	_add_rotation(spine, Vector3(-frame.tuck * profile.tuck_spine_pitch, frame.edge * 0.08, carve_roll * -0.38))
	_add_rotation(chest, Vector3(-frame.tuck * 0.18, -frame.edge * 0.12, carve_roll * -0.28))
	_add_rotation(head, Vector3(frame.tuck * 0.24, frame.edge * 0.08, carve_roll * -0.16))
	_apply_leg_flex(flex, frame.edge, deep_carve)
	_position_targets[pelvis] = Vector3(0.0, 0.96 - flex * 0.22, 0.0)

	if absf(frame.edge) > 0.08:
		_current_pose_name = "Deep Carve %s" % ("Left" if frame.edge < 0.0 else "Right") if deep_carve > 0.5 else "Carve %s" % ("Left" if frame.edge < 0.0 else "Right")
		var inside_arm := clampf(absf(frame.edge), 0.0, 1.0)
		_add_rotation(left_shoulder, Vector3(-0.28, 0.0, -0.2 - frame.edge * 0.24 * inside_arm))
		_add_rotation(right_shoulder, Vector3(-0.28, 0.0, 0.2 - frame.edge * 0.24 * inside_arm))
	else:
		_add_rotation(left_shoulder, Vector3(-0.24, 0.0, -0.18))
		_add_rotation(right_shoulder, Vector3(-0.24, 0.0, 0.18))

	if frame.tuck > 0.05:
		_current_pose_name = "Tuck"
		_add_rotation(left_shoulder, Vector3(-profile.tuck_arm_pitch * frame.tuck, -0.16, -0.26))
		_add_rotation(right_shoulder, Vector3(-profile.tuck_arm_pitch * frame.tuck, 0.16, 0.26))
		_add_rotation(left_elbow, Vector3(-0.9 * frame.tuck, 0.0, 0.0))
		_add_rotation(right_elbow, Vector3(-0.9 * frame.tuck, 0.0, 0.0))

	if frame.braking:
		_current_pose_name = "Hockey Stop %s" % ("Left" if skid_side < 0.0 else "Right")
		var brake_yaw := skid_side * profile.brake_ski_yaw
		_add_rotation(pelvis, Vector3(0.05, -brake_yaw * 0.35, -skid_side * 0.16))
		_add_rotation(chest, Vector3(-0.08, brake_yaw * 0.48, skid_side * 0.12))
		_add_rotation(left_ski, Vector3(0.0, brake_yaw, -skid_side * 0.11))
		_add_rotation(right_ski, Vector3(0.0, brake_yaw, -skid_side * 0.11))
		_add_rotation(left_shoulder, Vector3(-0.42, -brake_yaw * 0.28, -0.25))
		_add_rotation(right_shoulder, Vector3(-0.42, -brake_yaw * 0.28, 0.25))

	if frame.compression > 0.08:
		_current_pose_name = "Jump Compression"

func _apply_air_pose(frame: SkierAnimationFrame) -> void:
	var yaw_speed := absf(frame.angular_velocity.y)
	var flip_speed := absf(frame.angular_velocity.x)
	var roll_speed := absf(frame.angular_velocity.z)
	var compact := maxf(
		clampf(yaw_speed / profile.spin_compact_threshold, 0.0, 1.0),
		clampf(flip_speed / profile.flip_compact_threshold, 0.0, 1.0)
	)
	var air_flex := 0.24 + compact * profile.air_tuck_strength
	_current_blend = compact
	_current_pose_name = "Air Neutral"
	_apply_leg_flex(air_flex, 0.0, 0.0)
	_position_targets[pelvis] = Vector3(0.0, 0.96 - air_flex * 0.18, 0.0)
	_add_rotation(spine, Vector3(-flip_speed * 0.025, -frame.angular_velocity.y * 0.035, -frame.angular_velocity.z * 0.06))

	if yaw_speed > 0.5:
		_current_pose_name = "Compact Spin %s" % ("Left" if frame.angular_velocity.y > 0.0 else "Right")
		_add_rotation(left_shoulder, Vector3(-0.78 * compact, -0.28, -0.22))
		_add_rotation(right_shoulder, Vector3(-0.78 * compact, 0.28, 0.22))
		_add_rotation(head, Vector3(0.0, signf(frame.angular_velocity.y) * 0.35, 0.0))
	if flip_speed > 0.6:
		_current_pose_name = "%s Tuck" % ("Frontflip" if frame.angular_velocity.x > 0.0 else "Backflip")
		_add_rotation(pelvis, Vector3(-signf(frame.angular_velocity.x) * 0.2, 0.0, 0.0))
		_add_rotation(spine, Vector3(-signf(frame.angular_velocity.x) * 0.32, 0.0, 0.0))
	if roll_speed > 0.55:
		_current_pose_name = "Cork %s" % ("Left" if frame.angular_velocity.z > 0.0 else "Right")
		_add_rotation(chest, Vector3(0.0, signf(frame.angular_velocity.z) * 0.24, -signf(frame.angular_velocity.z) * 0.38))
		_add_rotation(pelvis, Vector3(0.0, -signf(frame.angular_velocity.z) * 0.16, signf(frame.angular_velocity.z) * 0.22))

	_apply_grab_pose(frame.grab_pose, frame)
	if frame.predicted_landing_time >= 0.0 and frame.predicted_landing_time < profile.landing_anticipation_time:
		var anticipation := 1.0 - frame.predicted_landing_time / profile.landing_anticipation_time
		_current_pose_name += " / Landing Ready"
		_add_rotation(left_hip, Vector3(-0.2 * anticipation, 0.0, 0.0))
		_add_rotation(right_hip, Vector3(-0.2 * anticipation, 0.0, 0.0))
		_add_rotation(left_knee, Vector3(0.45 * anticipation, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(0.45 * anticipation, 0.0, 0.0))
		_add_rotation(left_shoulder, Vector3(-0.22 * anticipation, 0.0, -0.16))
		_add_rotation(right_shoulder, Vector3(-0.22 * anticipation, 0.0, 0.16))

func _apply_trick_layer(frame: SkierAnimationFrame) -> void:
	var strength := clampf(frame.gesture_strength, 0.0, 1.0)
	match frame.trick_phase:
		TrickCommand.PresentationPhase.SETUP:
			_current_pose_name = "Flick Setup"
			var direction := frame.gesture_direction.x
			_position_targets[pelvis] += Vector3(direction * 0.04, -profile.flick_setup_depth * strength, 0.05 * strength)
			_add_rotation(pelvis, Vector3(-0.2 * strength, direction * 0.08, -direction * 0.18))
			_add_rotation(spine, Vector3(-0.28 * strength, -direction * 0.1, direction * 0.12))
			_add_rotation(left_knee, Vector3(0.55 * strength, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.55 * strength, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(-0.35 * strength, 0.0, -0.12))
			_add_rotation(right_shoulder, Vector3(-0.35 * strength, 0.0, 0.12))
		TrickCommand.PresentationPhase.RELEASE:
			_current_pose_name = "Flick Release"
			_position_targets[pelvis] += Vector3.UP * profile.flick_pop_extension * maxf(0.7, strength)
			_add_rotation(left_knee, Vector3(-0.35, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-0.35, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(0.22, 0.0, -0.28))
			_add_rotation(right_shoulder, Vector3(0.22, 0.0, 0.28))
		TrickCommand.PresentationPhase.ROTATE:
			_apply_command_rotation_pose(frame)
		TrickCommand.PresentationPhase.OPEN:
			_current_pose_name = "Open / Landing Ready"
			_add_rotation(left_hip, Vector3(0.18, 0.0, -0.08))
			_add_rotation(right_hip, Vector3(0.18, 0.0, 0.08))
			_add_rotation(left_knee, Vector3(-0.32, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-0.32, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(0.12, 0.0, -0.52))
			_add_rotation(right_shoulder, Vector3(0.12, 0.0, 0.52))
		TrickCommand.PresentationPhase.LANDING:
			_current_pose_name = "Landing Ready"

func _apply_command_rotation_pose(frame: SkierAnimationFrame) -> void:
	var progress_wave := sin(clampf(frame.rotation_progress, 0.0, 1.0) * PI)
	match frame.trick_kind:
		TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT:
			var side := -1.0 if frame.trick_kind == TrickCommand.Kind.SPIN_LEFT else 1.0
			_current_pose_name = "Spin %s" % ("Left" if side < 0.0 else "Right")
			_add_rotation(pelvis, Vector3(-0.14, side * 0.2, side * 0.08))
			_add_rotation(chest, Vector3(-0.08, -side * 0.42, -side * 0.12))
			_add_rotation(head, Vector3(0.0, side * (profile.spin_head_spot - 0.2 + progress_wave * 0.2), 0.0))
			_add_rotation(left_shoulder, Vector3(-0.72, -side * 0.18, -0.34))
			_add_rotation(right_shoulder, Vector3(-0.72, -side * 0.18, 0.34))
		TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP:
			var side := 1.0 if frame.trick_kind == TrickCommand.Kind.FRONTFLIP else -1.0
			_current_pose_name = "%s Tuck" % ("Frontflip" if side > 0.0 else "Backflip")
			_add_rotation(pelvis, Vector3(-side * 0.3, 0.0, 0.0))
			_add_rotation(spine, Vector3(-side * (0.28 + progress_wave * 0.22), 0.0, 0.0))
			_add_rotation(left_hip, Vector3(-0.32 * progress_wave, 0.0, 0.0))
			_add_rotation(right_hip, Vector3(-0.32 * progress_wave, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(0.62 * progress_wave, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.62 * progress_wave, 0.0, 0.0))
		TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT:
			var side := -1.0 if frame.trick_kind == TrickCommand.Kind.CORK_LEFT else 1.0
			_current_pose_name = "Cork %s" % ("Left" if side < 0.0 else "Right")
			_add_rotation(balance_root, Vector3(0.0, side * 0.12, side * 0.18))
			_add_rotation(pelvis, Vector3(-0.22, -side * 0.2, side * 0.46))
			_add_rotation(spine, Vector3(-0.3, side * 0.28, -side * 0.36))
			_add_rotation(chest, Vector3(-0.12, side * 0.34, -side * 0.38))
			_add_rotation(head, Vector3(0.12, -side * 0.25, side * 0.16))
			_add_rotation(left_shoulder, Vector3(-0.6, side * 0.2, -0.56))
			_add_rotation(right_shoulder, Vector3(-0.42, side * 0.2, 0.4))

func _apply_grind_pose(frame: SkierAnimationFrame) -> void:
	var balance := frame.rail_balance
	var flex := profile.rail_knee_flex + clampf(frame.rail_speed / 45.0, 0.0, 1.0) * 0.12
	_current_blend = balance
	_current_pose_name = "50-50 Grind"
	_apply_leg_flex(flex, balance * 0.3, absf(balance))
	_position_targets[pelvis] = Vector3(balance * 0.05, 0.96 - flex * 0.22, 0.0)
	_add_rotation(balance_root, Vector3(0.0, balance * profile.rail_counter_rotation, -balance * profile.rail_balance_lean))
	_add_rotation(pelvis, Vector3(-0.08, -balance * 0.32, balance * 0.2))
	_add_rotation(chest, Vector3(0.04, balance * 0.46, -balance * 0.18))
	_add_rotation(left_shoulder, Vector3(-0.25, balance * 0.25, -0.62))
	_add_rotation(right_shoulder, Vector3(-0.25, balance * 0.25, 0.62))
	if absf(balance) > 0.35:
		_current_pose_name = "Boardslide %s" % ("Left" if balance < 0.0 else "Right")
		_add_rotation(left_ski, Vector3(0.0, balance * 0.65, 0.0))
		_add_rotation(right_ski, Vector3(0.0, balance * 0.65, 0.0))

func _apply_bail_pose(frame: SkierAnimationFrame) -> void:
	var phase := _elapsed * profile.bail_flail_speed
	_current_blend = 1.0
	_current_pose_name = "Bail Tumble"
	_add_rotation(pelvis, Vector3(sin(phase) * 0.3, cos(phase * 0.7) * 0.4, sin(phase * 0.5) * 0.45))
	_add_rotation(spine, Vector3(cos(phase * 0.8) * 0.42, sin(phase) * 0.25, cos(phase * 0.6) * 0.36))
	_add_rotation(left_shoulder, Vector3(-1.0 + sin(phase) * 0.5, 0.3, -0.8))
	_add_rotation(right_shoulder, Vector3(-0.7 + cos(phase) * 0.55, -0.3, 0.8))
	_add_rotation(left_hip, Vector3(-0.5 + cos(phase * 0.8) * 0.35, 0.0, -0.35))
	_add_rotation(right_hip, Vector3(-0.25 + sin(phase * 0.7) * 0.4, 0.0, 0.35))
	_add_rotation(left_knee, Vector3(0.9, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(0.55, 0.0, 0.0))
	_add_rotation(left_ski, Vector3(0.0, -0.35, -0.2))
	_add_rotation(right_ski, Vector3(0.0, 0.4, 0.24))

func _apply_grab_pose(pose: int, frame: SkierAnimationFrame) -> void:
	if pose == 0:
		_grab_hand = null
		return
	_layer_weight = frame.grab_amount if frame.grab_amount > 0.0 else 1.0
	match pose:
		1:
			_current_pose_name = "Safety Grab Left"
			_add_rotation(left_shoulder, Vector3(-0.35, 0.12, -1.15))
			_add_rotation(left_elbow, Vector3(-1.0, 0.0, -0.2))
			_add_rotation(left_hip, Vector3(-0.28, 0.0, -0.18))
			_add_rotation(left_knee, Vector3(0.8, 0.0, 0.0))
		2:
			_current_pose_name = "Safety Grab Right"
			_add_rotation(right_shoulder, Vector3(-0.35, -0.12, 1.15))
			_add_rotation(right_elbow, Vector3(-1.0, 0.0, 0.2))
			_add_rotation(right_hip, Vector3(-0.28, 0.0, 0.18))
			_add_rotation(right_knee, Vector3(0.8, 0.0, 0.0))
		3:
			_current_pose_name = "Mute Grab Left"
			_add_rotation(left_shoulder, Vector3(-0.55, -0.45, -0.95))
			_add_rotation(left_elbow, Vector3(-1.12, 0.0, -0.25))
			_add_rotation(right_knee, Vector3(0.78, 0.0, 0.0))
		4:
			_current_pose_name = "Mute Grab Right"
			_add_rotation(right_shoulder, Vector3(-0.55, 0.45, 0.95))
			_add_rotation(right_elbow, Vector3(-1.12, 0.0, 0.25))
			_add_rotation(left_knee, Vector3(0.78, 0.0, 0.0))
		5, 6:
			var side := -1.0 if pose == 5 else 1.0
			_current_pose_name = "Japan Grab %s" % ("Left" if side < 0.0 else "Right")
			_add_rotation(spine, Vector3(-0.35, side * 0.18, side * 0.24))
			_add_rotation(left_knee if side < 0.0 else right_knee, Vector3(1.05, 0.0, side * 0.12))
			_add_rotation(left_ski if side < 0.0 else right_ski, Vector3(0.22, 0.0, side * 0.2))
			_add_rotation(left_shoulder if side < 0.0 else right_shoulder, Vector3(-0.42, side * 0.32, side * 1.12))
		7:
			_current_pose_name = "Tail Grab"
			_add_rotation(spine, Vector3(-0.38, 0.28, 0.0))
			_add_rotation(right_shoulder, Vector3(-0.55, 0.5, 1.0))
			_add_rotation(right_ski, Vector3(0.22, 0.0, 0.0))
		8:
			_current_pose_name = "Nose Grab"
			_add_rotation(spine, Vector3(-0.5, -0.18, 0.0))
			_add_rotation(left_shoulder, Vector3(-0.72, -0.4, -0.9))
			_add_rotation(left_ski, Vector3(-0.18, 0.0, 0.0))
		9:
			_current_pose_name = "Double Grab"
			_add_rotation(left_shoulder, Vector3(-0.6, 0.2, -1.0))
			_add_rotation(right_shoulder, Vector3(-0.6, -0.2, 1.0))
			_add_rotation(left_elbow, Vector3(-0.95, 0.0, 0.0))
			_add_rotation(right_elbow, Vector3(-0.95, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(0.8, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.8, 0.0, 0.0))
		10:
			_current_pose_name = "Spread Eagle"
			_add_rotation(left_hip, Vector3(0.3, -0.2, -0.55))
			_add_rotation(right_hip, Vector3(0.3, 0.2, 0.55))
			_add_rotation(left_shoulder, Vector3(0.0, 0.0, -1.35))
			_add_rotation(right_shoulder, Vector3(0.0, 0.0, 1.35))
		11:
			_current_pose_name = "Daffy"
			_add_rotation(left_hip, Vector3(-0.7, 0.0, 0.0))
			_add_rotation(right_hip, Vector3(0.48, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(0.28, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(0.08, 0.0, 0.0))
	_apply_grab_reach(pose, frame, _layer_weight)
	_layer_weight = 1.0

func _apply_grab_reach(pose: int, frame: SkierAnimationFrame, amount: float) -> void:
	var reach_amount := clampf(amount, 0.0, 1.0)
	if pose not in [TrickController.GrabPose.SPREAD_EAGLE, TrickController.GrabPose.DAFFY]:
		_position_targets[chest] = Vector3(0.0, 0.42 - profile.grab_chest_drop * reach_amount, 0.1 * reach_amount)
		_add_rotation(spine, Vector3(-0.34 * reach_amount, 0.0, 0.0))
		_add_rotation(left_hip, Vector3(-0.34 * reach_amount, 0.0, 0.0))
		_add_rotation(right_hip, Vector3(-0.34 * reach_amount, 0.0, 0.0))
		_add_rotation(left_knee, Vector3(profile.grab_leg_tuck * reach_amount, 0.0, 0.0))
		_add_rotation(right_knee, Vector3(profile.grab_leg_tuck * reach_amount, 0.0, 0.0))
	match pose:
		TrickController.GrabPose.SAFETY_LEFT, TrickController.GrabPose.JAPAN_LEFT:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
		TrickController.GrabPose.SAFETY_RIGHT, TrickController.GrabPose.JAPAN_RIGHT:
			_aim_arm_at(right_shoulder, right_elbow, right_hand, right_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
		TrickController.GrabPose.MUTE_LEFT:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, right_ski.to_global(Vector3(0.0, 0.04, 0.0)), reach_amount)
		TrickController.GrabPose.MUTE_RIGHT:
			_aim_arm_at(right_shoulder, right_elbow, right_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.0)), reach_amount)
		TrickController.GrabPose.TAIL:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.78)), reach_amount)
		TrickController.GrabPose.NOSE:
			_aim_arm_at(right_shoulder, right_elbow, right_hand, right_ski.to_global(Vector3(0.0, 0.04, -0.9)), reach_amount)
		TrickController.GrabPose.DOUBLE:
			_aim_arm_at(left_shoulder, left_elbow, left_hand, left_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
			_aim_arm_at(right_shoulder, right_elbow, right_hand, right_ski.to_global(Vector3(0.0, 0.04, 0.05)), reach_amount)
	if absf(frame.grab_tweak.x) > 0.05:
		_add_rotation(left_ski, Vector3(0.0, frame.grab_tweak.x * 0.18 * reach_amount, -frame.grab_tweak.x * 0.12 * reach_amount))
		_add_rotation(right_ski, Vector3(0.0, -frame.grab_tweak.x * 0.18 * reach_amount, frame.grab_tweak.x * 0.12 * reach_amount))

func _aim_arm_at(shoulder: Node3D, elbow: Node3D, hand: Node3D, target_world: Vector3, amount: float) -> void:
	var target_local := shoulder.to_local(target_world)
	if target_local.length_squared() < 0.0001:
		return
	var upper := 0.42
	var lower := 0.37
	var raw_distance := target_local.length()
	var distance := clampf(raw_distance, absf(upper - lower) + 0.01, upper + lower - 0.005)
	var direction := target_local.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var pole := Vector3.FORWARD
	var bend_axis := (pole - direction * pole.dot(direction)).normalized()
	if bend_axis.length_squared() < 0.01:
		bend_axis = Vector3.RIGHT
	var elbow_target := direction * along + bend_axis * height * (-1.0 if shoulder == left_shoulder else 1.0)
	var shoulder_rotation := Quaternion(Vector3.DOWN, elbow_target.normalized())
	var lower_direction := (direction * distance - elbow_target).normalized()
	var elbow_rotation := Quaternion(Vector3.DOWN, shoulder_rotation.inverse() * lower_direction)
	var current_target := _rotation_targets[shoulder] as Vector3
	_rotation_targets[shoulder] = current_target.lerp(shoulder_rotation.get_euler(), amount)
	_rotation_targets[elbow] = (_rotation_targets[elbow] as Vector3).lerp(elbow_rotation.get_euler(), amount)
	_grab_hand = hand
	_grab_target_world = target_world

func _apply_leg_flex(flex: float, edge: float, deep_carve: float) -> void:
	var left_bias := clampf(-edge, -1.0, 1.0)
	var right_bias := clampf(edge, -1.0, 1.0)
	_add_rotation(left_hip, Vector3(-0.12 - flex * 0.48 + left_bias * 0.08, 0.0, -edge * 0.07))
	_add_rotation(right_hip, Vector3(-0.12 - flex * 0.48 + right_bias * 0.08, 0.0, -edge * 0.07))
	_add_rotation(left_knee, Vector3(flex * 1.05 + maxf(0.0, left_bias) * deep_carve * 0.2, 0.0, 0.0))
	_add_rotation(right_knee, Vector3(flex * 1.05 + maxf(0.0, right_bias) * deep_carve * 0.2, 0.0, 0.0))
	_add_rotation(left_boot, Vector3(-flex * 0.42, 0.0, -edge * 0.17))
	_add_rotation(right_boot, Vector3(-flex * 0.42, 0.0, -edge * 0.17))

func _apply_reaction(frame: SkierAnimationFrame, delta: float) -> void:
	if _reaction_event < 0 or _reaction_duration <= 0.0:
		return
	_reaction_time += delta
	var normalized := clampf(_reaction_time / _reaction_duration, 0.0, 1.0)
	var pulse := sin(normalized * PI)
	match _reaction_event:
		AnimationEvent.POP:
			_current_pose_name = "Pop Extension"
			_position_targets[pelvis] += Vector3.UP * pulse * 0.12 * _reaction_strength
			_add_rotation(left_hip, Vector3(pulse * 0.22, 0.0, 0.0))
			_add_rotation(right_hip, Vector3(pulse * 0.22, 0.0, 0.0))
			_add_rotation(left_knee, Vector3(-pulse * 0.42, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(-pulse * 0.42, 0.0, 0.0))
			_add_rotation(left_shoulder, Vector3(pulse * 0.25, 0.0, -pulse * 0.12))
			_add_rotation(right_shoulder, Vector3(pulse * 0.25, 0.0, pulse * 0.12))
		AnimationEvent.LAND_CLEAN, AnimationEvent.LAND_SKETCHY, AnimationEvent.LAND_HARD:
			var depth := 0.16
			if _reaction_event == AnimationEvent.LAND_SKETCHY: depth = 0.28
			if _reaction_event == AnimationEvent.LAND_HARD: depth = 0.4
			_position_targets[pelvis] += Vector3(0.0, -pulse * depth * _reaction_strength, 0.0)
			_add_rotation(left_hip, Vector3(-pulse * depth, 0.0, -_reaction_side * pulse * 0.08))
			_add_rotation(right_hip, Vector3(-pulse * depth, 0.0, -_reaction_side * pulse * 0.08))
			_add_rotation(left_knee, Vector3(pulse * depth * 1.7, 0.0, 0.0))
			_add_rotation(right_knee, Vector3(pulse * depth * 1.7, 0.0, 0.0))
			_add_rotation(chest, Vector3(pulse * depth * 0.35, 0.0, _reaction_side * pulse * depth))
		AnimationEvent.GRIND_ENTER, AnimationEvent.GRIND_EXIT:
			_position_targets[pelvis] += Vector3(0.0, -pulse * 0.08, 0.0)
	if normalized >= 1.0:
		_reaction_event = -1

func _apply_secondary_motion(frame: SkierAnimationFrame) -> void:
	var speed_sway := clampf(frame.speed_ratio, 0.0, 1.0)
	var pole_sway := sin(_elapsed * lerpf(2.0, 7.0, speed_sway)) * 0.045 * speed_sway
	_add_rotation(left_pole, Vector3(pole_sway, 0.0, -0.08))
	_add_rotation(right_pole, Vector3(-pole_sway, 0.0, 0.08))
	if frame.switch_stance:
		_add_rotation(chest, Vector3(0.0, 0.08, 0.0))
		_add_rotation(head, Vector3(0.0, -0.12, 0.0))

func _blend_targets(delta: float) -> void:
	var rotation_weight := 1.0 - exp(-profile.pose_response * delta)
	var position_weight := 1.0 - exp(-profile.fast_pose_response * delta)
	for key: Variant in _rotation_targets.keys():
		var joint := key as Node3D
		var target := _rotation_targets[key] as Vector3
		joint.rotation = Vector3(
			lerp_angle(joint.rotation.x, target.x, rotation_weight),
			lerp_angle(joint.rotation.y, target.y, rotation_weight),
			lerp_angle(joint.rotation.z, target.z, rotation_weight)
		)
	for key: Variant in _position_targets.keys():
		var joint := key as Node3D
		joint.position = joint.position.lerp(_position_targets[key] as Vector3, position_weight)

func _add_rotation(joint: Node3D, value: Vector3) -> void:
	_rotation_targets[joint] = (_rotation_targets.get(joint, Vector3.ZERO) as Vector3) + value * _layer_weight

func _reset_pose_immediately() -> void:
	_reset_targets()
	for key: Variant in _rotation_targets.keys():
		(key as Node3D).rotation = _rotation_targets[key] as Vector3
	for key: Variant in _position_targets.keys():
		(key as Node3D).position = _position_targets[key] as Vector3

func _build_articulated_rig() -> void:
	var jacket := _material(Color("#f24f68"), 0.78, 0.05)
	var pants := _material(Color("#243543"), 0.82, 0.0)
	var skin := _material(Color("#e8b58e"), 0.9, 0.0)
	var dark := _material(Color("#132532"), 0.5, 0.25)
	var accent := _material(Color("#ffc857"), 0.65, 0.05)
	var lens := _material(Color("#5ac8fa"), 0.2, 0.55)

	balance_root = _joint("BalanceRoot", self, Vector3.ZERO)
	pelvis = _joint("Pelvis", balance_root, Vector3(0.0, 0.96, 0.0))
	_add_box(pelvis, "PelvisMesh", Vector3(0.52, 0.22, 0.3), Vector3(0.0, 0.05, 0.0), pants)
	spine = _joint("Spine", pelvis, Vector3(0.0, 0.14, 0.0))
	_add_capsule(spine, "TorsoMesh", 0.31, 0.72, Vector3(0.0, 0.34, 0.0), jacket)
	chest = _joint("Chest", spine, Vector3(0.0, 0.42, 0.0))
	_add_box(chest, "ShoulderJacket", Vector3(0.74, 0.2, 0.34), Vector3(0.0, 0.14, 0.0), jacket)
	head = _joint("Head", chest, Vector3(0.0, 0.5, 0.0))
	_add_sphere(head, "HeadMesh", 0.2, Vector3(0.0, 0.11, 0.0), skin)
	_add_sphere(head, "Helmet", 0.225, Vector3(0.0, 0.19, 0.02), dark, Vector3(1.0, 0.72, 1.0))
	_add_box(head, "Goggles", Vector3(0.29, 0.105, 0.08), Vector3(0.0, 0.13, -0.19), lens)

	left_hip = _joint("LeftHip", pelvis, Vector3(-0.24, -0.04, 0.0))
	right_hip = _joint("RightHip", pelvis, Vector3(0.24, -0.04, 0.0))
	_add_capsule(left_hip, "LeftThigh", 0.105, 0.56, Vector3(0.0, -0.26, 0.0), pants)
	_add_capsule(right_hip, "RightThigh", 0.105, 0.56, Vector3(0.0, -0.26, 0.0), pants)
	left_knee = _joint("LeftKnee", left_hip, Vector3(0.0, -0.52, 0.0))
	right_knee = _joint("RightKnee", right_hip, Vector3(0.0, -0.52, 0.0))
	_add_capsule(left_knee, "LeftShin", 0.09, 0.52, Vector3(0.0, -0.24, 0.0), pants)
	_add_capsule(right_knee, "RightShin", 0.09, 0.52, Vector3(0.0, -0.24, 0.0), pants)
	left_boot = _joint("LeftBoot", left_knee, Vector3(0.0, -0.49, -0.03))
	right_boot = _joint("RightBoot", right_knee, Vector3(0.0, -0.49, -0.03))
	_add_box(left_boot, "LeftBootMesh", Vector3(0.2, 0.17, 0.4), Vector3(0.0, -0.02, -0.09), dark)
	_add_box(right_boot, "RightBootMesh", Vector3(0.2, 0.17, 0.4), Vector3(0.0, -0.02, -0.09), dark)
	left_ski = _joint("LeftSki", left_boot, Vector3(0.0, -0.12, -0.08))
	right_ski = _joint("RightSki", right_boot, Vector3(0.0, -0.12, -0.08))
	_add_box(left_ski, "LeftSkiMesh", Vector3(0.14, 0.055, 2.15), Vector3(0.0, 0.0, -0.12), accent)
	_add_box(right_ski, "RightSkiMesh", Vector3(0.14, 0.055, 2.15), Vector3(0.0, 0.0, -0.12), accent)

	left_shoulder = _joint("LeftShoulder", chest, Vector3(-0.4, 0.24, 0.0))
	right_shoulder = _joint("RightShoulder", chest, Vector3(0.4, 0.24, 0.0))
	_add_capsule(left_shoulder, "LeftUpperArm", 0.085, 0.46, Vector3(0.0, -0.21, 0.0), jacket)
	_add_capsule(right_shoulder, "RightUpperArm", 0.085, 0.46, Vector3(0.0, -0.21, 0.0), jacket)
	left_elbow = _joint("LeftElbow", left_shoulder, Vector3(0.0, -0.42, 0.0))
	right_elbow = _joint("RightElbow", right_shoulder, Vector3(0.0, -0.42, 0.0))
	_add_capsule(left_elbow, "LeftForearm", 0.07, 0.4, Vector3(0.0, -0.18, 0.0), jacket)
	_add_capsule(right_elbow, "RightForearm", 0.07, 0.4, Vector3(0.0, -0.18, 0.0), jacket)
	left_hand = _joint("LeftHand", left_elbow, Vector3(0.0, -0.37, 0.0))
	right_hand = _joint("RightHand", right_elbow, Vector3(0.0, -0.37, 0.0))
	_add_sphere(left_hand, "LeftGlove", 0.09, Vector3.ZERO, dark)
	_add_sphere(right_hand, "RightGlove", 0.09, Vector3.ZERO, dark)
	left_pole = _joint("LeftPole", left_hand, Vector3.ZERO)
	right_pole = _joint("RightPole", right_hand, Vector3.ZERO)
	_add_cylinder(left_pole, "LeftPoleMesh", 0.022, 1.15, Vector3(0.0, -0.52, 0.08), dark)
	_add_cylinder(right_pole, "RightPoleMesh", 0.022, 1.15, Vector3(0.0, -0.52, 0.08), dark)
	_reset_pose_immediately()

func _joint(joint_name: String, parent: Node3D, position: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = position
	parent.add_child(joint)
	return joint

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _add_box(parent: Node3D, mesh_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)

func _add_capsule(parent: Node3D, mesh_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)

func _add_sphere(parent: Node3D, mesh_name: String, radius: float, position: Vector3, material: Material, scale: Vector3 = Vector3.ONE) -> void:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale
	instance.material_override = material
	parent.add_child(instance)

func _add_cylinder(parent: Node3D, mesh_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
