class_name FlickTrickInterpreter
extends RefCounted

enum Context { GROUND, AIR, GRIND, BAIL }
enum RotationFamily { NONE, SPIN, FLIP, CORK }

var profile: FlickTrickProfile
var _command := TrickCommand.new()
var _last_context := Context.BAIL
var _setup_active := false
var _setup_hold_time := 0.0
var _setup_release_time := 0.0
var _setup_peak_depth := 0.0
var _gesture_armed := true
var _cooldown_remaining := 0.0
var _left_grab_armed := true
var _right_grab_armed := true
var _left_grab_active := false
var _right_grab_active := false
var _history_clock := 0.0
var _stick_history: Array[Dictionary] = []
var _takeoff_rotation_committed := false
var _takeoff_kind := TrickCommand.Kind.NONE
var _air_authority_remaining := 0.0
var _pending_takeoff_impulse := Vector3.ZERO
var _takeoff_release_elapsed := 0.0
var _takeoff_release_fraction := 0.0

func _init(value: FlickTrickProfile = null) -> void:
	profile = value if value != null else preload("res://resources/physics/default_flick_trick_profile.tres")

func step(sample: TrickInputSample, context: int, delta: float) -> TrickCommand:
	_record_stick_sample(sample.right_stick, delta)
	_command.reset()
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if context == Context.BAIL:
		reset()
		_last_context = context
		return _command
	if context != _last_context:
		_enter_context(sample, context)
	_command.left_trigger = sample.left_trigger
	_command.right_trigger = sample.right_trigger
	if context == Context.AIR:
		_seed_pending_takeoff_release(delta)
	if context == Context.AIR or context == Context.GRIND:
		_update_trigger_grabs(sample)
		if _left_grab_active or _right_grab_active:
			_apply_grab_command(sample)
			_last_context = context
			return _command
	match context:
		Context.GROUND: _step_ground(sample, delta, false)
		Context.AIR: _step_air(sample)
		Context.GRIND: _step_grind(sample, delta)
	_last_context = context
	return _command

func reset() -> void:
	_clear_setup_state()
	_gesture_armed = true
	_cooldown_remaining = 0.0
	_left_grab_armed = true
	_right_grab_armed = true
	_left_grab_active = false
	_right_grab_active = false
	_history_clock = 0.0
	_stick_history.clear()
	_clear_takeoff_commitment()
	_last_context = Context.BAIL
	_command.reset()

func snapshot() -> Dictionary:
	return {
		"setup_active": _setup_active,
		"setup_hold_time": _setup_hold_time,
		"setup_peak_depth": _setup_peak_depth,
		"takeoff_rotation_committed": _takeoff_rotation_committed,
		"takeoff_kind": _takeoff_kind,
		"air_authority_remaining": _air_authority_remaining,
		"takeoff_release_fraction": _takeoff_release_fraction,
		"takeoff_release_elapsed": _takeoff_release_elapsed,
		"pending_takeoff_impulse": _pending_takeoff_impulse,
	}

func _enter_context(sample: TrickInputSample, context: int) -> void:
	_clear_setup_state()
	_gesture_armed = sample.right_stick.length() <= profile.center_reset_threshold
	if context == Context.AIR:
		# A trigger used for braking or tucking must be released after takeoff.
		_left_grab_armed = sample.left_trigger < profile.trigger_press_threshold
		_right_grab_armed = sample.right_trigger < profile.trigger_press_threshold
		_left_grab_active = false
		_right_grab_active = false
	elif context == Context.GROUND:
		_clear_takeoff_commitment()
		_left_grab_active = false
		_right_grab_active = false
	elif context == Context.GRIND:
		_clear_takeoff_commitment()

func _step_ground(sample: TrickInputSample, delta: float, rail: bool) -> void:
	var stick := sample.right_stick
	if stick.y >= profile.setup_threshold:
		if not _setup_active:
			_setup_active = true
			_setup_hold_time = 0.0
			_setup_release_time = 0.0
			_setup_peak_depth = stick.y
		_setup_hold_time += delta
		_setup_peak_depth = maxf(_setup_peak_depth, stick.y)
		_gesture_armed = false
		_command.phase = TrickCommand.PresentationPhase.SETUP
		_command.gesture_strength = clampf(stick.length(), 0.0, 1.0)
		_command.setup_depth = _setup_peak_depth
		_command.setup_duration = _setup_hold_time
		_command.setup_quality = _setup_quality(0.0)
		return
	if not _setup_active:
		if stick.length() <= profile.center_reset_threshold and _cooldown_remaining <= 0.0:
			_gesture_armed = true
		return
	_setup_release_time += delta
	if _setup_release_time > profile.maximum_gesture_duration + profile.input_buffer_seconds:
		_clear_setup_state()
		return
	if stick.length() < profile.flick_threshold:
		return
	var kind := _classify_takeoff(stick, rail)
	if kind == TrickCommand.Kind.NONE:
		return
	_commit_takeoff(kind, stick, delta)

func _step_air(sample: TrickInputSample) -> void:
	var stick := sample.right_stick
	if stick.length() <= profile.center_reset_threshold:
		if _cooldown_remaining <= 0.0:
			_gesture_armed = true
		return
	if not _gesture_armed or _cooldown_remaining > 0.0 or stick.length() < profile.flick_threshold:
		return
	var requested := _classify_air(stick)
	if requested == TrickCommand.Kind.NONE:
		return

	# Spin and cork authority come from takeoff. Air input can only continue or
	# check the already-committed family. Flip input remains on the legacy air
	# path until a dedicated preload mapping can be introduced without stealing
	# the established down-to-up straight-pop gesture.
	if _rotation_family(requested) in [RotationFamily.SPIN, RotationFamily.CORK]:
		if not _takeoff_rotation_committed:
			_consume_rejected_air_gesture()
			return
		if _rotation_family(requested) != _rotation_family(_takeoff_kind):
			_consume_rejected_air_gesture()
			return
		_commit_air_management(requested, stick)
		return

	# Do not let a legacy flip input replace a spin/cork family that was already
	# committed at the lip. This preserves maneuver-family commitment even while
	# flip preload is still being migrated.
	if _takeoff_rotation_committed:
		_consume_rejected_air_gesture()
		return
	_commit_legacy_air(requested, stick)

func _step_grind(sample: TrickInputSample, delta: float) -> void:
	var stick := sample.right_stick
	if _setup_active or stick.y >= profile.setup_threshold:
		_step_ground(sample, delta, true)
		return
	if stick.length() <= profile.center_reset_threshold:
		if _cooldown_remaining <= 0.0:
			_gesture_armed = true
		return
	if not _gesture_armed or _cooldown_remaining > 0.0 or absf(stick.x) < profile.flick_threshold:
		return
	_commit_simple(TrickCommand.Kind.RAIL_SLIDE_LEFT if stick.x < 0.0 else TrickCommand.Kind.RAIL_SLIDE_RIGHT, stick, false)

func _classify_takeoff(stick: Vector2, rail: bool) -> int:
	if stick.y <= -profile.flick_threshold and absf(stick.x) < profile.flick_threshold:
		return TrickCommand.Kind.RAIL_POP if rail else TrickCommand.Kind.POP
	if absf(stick.x) < profile.flick_threshold:
		return TrickCommand.Kind.NONE
	if stick.y <= -0.42:
		return TrickCommand.Kind.CORK_LEFT if stick.x < 0.0 else TrickCommand.Kind.CORK_RIGHT
	return TrickCommand.Kind.SPIN_LEFT if stick.x < 0.0 else TrickCommand.Kind.SPIN_RIGHT

func _classify_air(stick: Vector2) -> int:
	if absf(stick.x) >= profile.flick_threshold and absf(stick.y) >= 0.42:
		return TrickCommand.Kind.CORK_LEFT if stick.x < 0.0 else TrickCommand.Kind.CORK_RIGHT
	if absf(stick.x) >= absf(stick.y):
		return TrickCommand.Kind.SPIN_LEFT if stick.x < 0.0 else TrickCommand.Kind.SPIN_RIGHT
	return TrickCommand.Kind.FRONTFLIP if stick.y < 0.0 else TrickCommand.Kind.BACKFLIP

func _commit_takeoff(kind: int, stick: Vector2, delta: float) -> void:
	var release_speed := _release_speed(stick)
	var quality := _setup_quality(release_speed)
	var command_strength := lerpf(profile.minimum_command_strength, 1.0, quality)
	var total_rotation_impulse := _rotation_impulse(kind, command_strength)
	_command.kind = kind
	_command.phase = TrickCommand.PresentationPhase.RELEASE
	_command.gesture_strength = command_strength
	_command.pop_strength = command_strength
	_command.setup_depth = _setup_peak_depth
	_command.setup_duration = _setup_hold_time
	_command.release_speed = release_speed
	_command.release_direction = stick.normalized() if stick.length_squared() > 0.0001 else Vector2.ZERO
	_command.setup_quality = quality
	_command.takeoff_rotation_committed = _is_preload_rotation_kind(kind)
	_command.committed = true
	if _command.takeoff_rotation_committed:
		_takeoff_rotation_committed = true
		_takeoff_kind = kind
		_air_authority_remaining = profile.air_authority_budget
		_begin_pending_takeoff_release(total_rotation_impulse)
		_command.rotation_impulse = _consume_pending_takeoff_release(delta)
	else:
		_clear_takeoff_commitment()
		_command.rotation_impulse = total_rotation_impulse
	_clear_setup_state()
	_gesture_armed = false
	_cooldown_remaining = profile.repeat_cooldown

func _commit_air_management(requested: int, stick: Vector2) -> void:
	if _air_authority_remaining <= 0.001:
		_consume_rejected_air_gesture()
		return
	var strength := clampf(stick.length(), 0.0, 1.0)
	var same_direction := requested == _takeoff_kind
	var requested_fraction := (profile.air_continue_fraction if same_direction else profile.air_check_fraction) * strength
	var authority := minf(requested_fraction, _air_authority_remaining)
	if authority <= 0.001:
		return
	_command.kind = _takeoff_kind
	_command.phase = TrickCommand.PresentationPhase.ROTATE
	_command.gesture_strength = strength
	_command.air_management = TrickCommand.AirManagement.CONTINUE if same_direction else TrickCommand.AirManagement.CHECK
	_command.air_management_strength = authority
	_command.rotation_impulse += _rotation_impulse(_takeoff_kind if same_direction else requested, authority)
	_command.committed = true
	_air_authority_remaining = maxf(0.0, _air_authority_remaining - authority)
	_gesture_armed = false
	_cooldown_remaining = profile.repeat_cooldown

func _commit_legacy_air(kind: int, stick: Vector2) -> void:
	_commit_simple(kind, stick, false)

func _commit_simple(kind: int, stick: Vector2, includes_pop: bool) -> void:
	_command.kind = kind
	_command.phase = TrickCommand.PresentationPhase.RELEASE if includes_pop else TrickCommand.PresentationPhase.ROTATE
	_command.gesture_strength = clampf(stick.length(), 0.0, 1.0)
	_command.pop_strength = lerpf(profile.minimum_command_strength, 1.0, _command.gesture_strength) if includes_pop else 0.0
	_command.rotation_impulse = _rotation_impulse(kind, _command.gesture_strength)
	_command.committed = true
	_clear_setup_state()
	_gesture_armed = false
	_cooldown_remaining = profile.repeat_cooldown

func _begin_pending_takeoff_release(total_impulse: Vector3) -> void:
	_pending_takeoff_impulse = total_impulse
	_takeoff_release_elapsed = 0.0
	_takeoff_release_fraction = 0.0

func _seed_pending_takeoff_release(delta: float) -> void:
	var release_impulse := _consume_pending_takeoff_release(delta)
	if release_impulse.length_squared() <= 0.0000001:
		return
	_command.kind = _takeoff_kind
	_command.phase = TrickCommand.PresentationPhase.ROTATE
	_command.rotation_impulse += release_impulse
	_command.committed = true

func _consume_pending_takeoff_release(delta: float) -> Vector3:
	if not _pending_takeoff_release_active():
		return Vector3.ZERO
	var duration := maxf(profile.takeoff_release_duration, 0.0)
	if duration <= 0.0001:
		var instant := _pending_takeoff_impulse * (1.0 - _takeoff_release_fraction)
		_takeoff_release_fraction = 1.0
		_takeoff_release_elapsed = duration
		return instant
	var previous_fraction := _takeoff_release_fraction
	_takeoff_release_elapsed = minf(_takeoff_release_elapsed + maxf(delta, 0.0), duration)
	var normalized_time := clampf(_takeoff_release_elapsed / duration, 0.0, 1.0)
	_takeoff_release_fraction = _smoothstep01(normalized_time)
	if _takeoff_release_elapsed >= duration:
		_takeoff_release_fraction = 1.0
	return _pending_takeoff_impulse * (_takeoff_release_fraction - previous_fraction)

func _pending_takeoff_release_active() -> bool:
	return _takeoff_rotation_committed and _pending_takeoff_impulse.length_squared() > 0.0000001 and _takeoff_release_fraction < 1.0

func _consume_rejected_air_gesture() -> void:
	_gesture_armed = false
	_cooldown_remaining = profile.repeat_cooldown

func _rotation_impulse(kind: int, strength: float) -> Vector3:
	match kind:
		TrickCommand.Kind.SPIN_LEFT: return Vector3(0.0, -profile.spin_impulse * strength, 0.0)
		TrickCommand.Kind.SPIN_RIGHT: return Vector3(0.0, profile.spin_impulse * strength, 0.0)
		TrickCommand.Kind.FRONTFLIP: return Vector3(profile.flip_impulse * strength, 0.0, 0.0)
		TrickCommand.Kind.BACKFLIP: return Vector3(-profile.flip_impulse * strength, 0.0, 0.0)
		TrickCommand.Kind.CORK_LEFT: return Vector3(0.0, -profile.cork_yaw_impulse * strength, -profile.cork_roll_impulse * strength)
		TrickCommand.Kind.CORK_RIGHT: return Vector3(0.0, profile.cork_yaw_impulse * strength, profile.cork_roll_impulse * strength)
	return Vector3.ZERO

func _setup_quality(release_speed: float) -> float:
	var depth := clampf((_setup_peak_depth - profile.setup_threshold) / maxf(1.0 - profile.setup_threshold, 0.001), 0.0, 1.0)
	var duration := clampf(_setup_hold_time / maxf(profile.setup_duration_reference, 0.001), 0.0, 1.0)
	var speed := clampf(release_speed / maxf(profile.release_speed_reference, 0.001), 0.0, 1.0)
	var weight_sum := maxf(profile.setup_depth_weight + profile.setup_duration_weight + profile.release_speed_weight, 0.001)
	return clampf((depth * profile.setup_depth_weight + duration * profile.setup_duration_weight + speed * profile.release_speed_weight) / weight_sum, 0.0, 1.0)

func _record_stick_sample(stick: Vector2, delta: float) -> void:
	_history_clock += maxf(delta, 0.0)
	_stick_history.append({"time": _history_clock, "stick": stick})
	var cutoff := _history_clock - maxf(profile.release_velocity_window, 0.001)
	while _stick_history.size() > 2 and float(_stick_history[1].time) < cutoff:
		_stick_history.pop_front()

func _release_speed(current: Vector2) -> float:
	if _stick_history.size() < 2:
		return 0.0
	var oldest: Dictionary = _stick_history[0]
	var elapsed := _history_clock - float(oldest.time)
	if elapsed <= 0.0001:
		return 0.0
	return (current - (oldest.stick as Vector2)).length() / elapsed

func _rotation_family(kind: int) -> int:
	match kind:
		TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT:
			return RotationFamily.SPIN
		TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP:
			return RotationFamily.FLIP
		TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT:
			return RotationFamily.CORK
	return RotationFamily.NONE

func _is_preload_rotation_kind(kind: int) -> bool:
	return _rotation_family(kind) in [RotationFamily.SPIN, RotationFamily.CORK]

func _clear_setup_state() -> void:
	_setup_active = false
	_setup_hold_time = 0.0
	_setup_release_time = 0.0
	_setup_peak_depth = 0.0

func _clear_takeoff_commitment() -> void:
	_takeoff_rotation_committed = false
	_takeoff_kind = TrickCommand.Kind.NONE
	_air_authority_remaining = 0.0
	_pending_takeoff_impulse = Vector3.ZERO
	_takeoff_release_elapsed = 0.0
	_takeoff_release_fraction = 0.0

func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _update_trigger_grabs(sample: TrickInputSample) -> void:
	if sample.left_trigger < profile.trigger_press_threshold:
		_left_grab_armed = true
		_left_grab_active = false
	elif _left_grab_armed:
		_left_grab_active = true
	if sample.right_trigger < profile.trigger_press_threshold:
		_right_grab_armed = true
		_right_grab_active = false
	elif _right_grab_armed:
		_right_grab_active = true

func _apply_grab_command(sample: TrickInputSample) -> void:
	_command.phase = TrickCommand.PresentationPhase.GRAB
	var amount := maxf(sample.left_trigger if _left_grab_active else 0.0, sample.right_trigger if _right_grab_active else 0.0)
	_command.grab_tweak = sample.right_stick
	_command.style_pose = _resolve_style_pose(_left_grab_active, _right_grab_active, sample.right_stick)
	if _command.style_pose != TrickController.StylePose.NONE:
		_command.style_amount = amount
	else:
		_command.grab_amount = amount
		_command.grab_pose = _resolve_grab_pose(_left_grab_active, _right_grab_active, sample.right_stick)
	_gesture_armed = false

func _resolve_grab_pose(left: bool, right: bool, style: Vector2) -> int:
	if left and right:
		return TrickController.GrabPose.DOUBLE
	if left:
		if style.x > 0.45: return TrickController.GrabPose.MUTE_LEFT
		if style.y < -0.45: return TrickController.GrabPose.JAPAN_LEFT
		if style.y > 0.45: return TrickController.GrabPose.TAIL
		return TrickController.GrabPose.SAFETY_LEFT
	if right:
		if style.x < -0.45: return TrickController.GrabPose.MUTE_RIGHT
		if style.y < -0.45: return TrickController.GrabPose.JAPAN_RIGHT
		if style.y > 0.45: return TrickController.GrabPose.NOSE
		return TrickController.GrabPose.SAFETY_RIGHT
	return TrickController.GrabPose.NONE

func _resolve_style_pose(left: bool, right: bool, style: Vector2) -> int:
	if not left or not right:
		return TrickController.StylePose.NONE
	if absf(style.x) > 0.45 and absf(style.x) >= absf(style.y):
		return TrickController.StylePose.SHIFTY_LEFT if style.x < 0.0 else TrickController.StylePose.SHIFTY_RIGHT
	if style.y < -0.45:
		return TrickController.StylePose.SPREAD_EAGLE
	if style.y > 0.45:
		return TrickController.StylePose.DAFFY
	return TrickController.StylePose.NONE
