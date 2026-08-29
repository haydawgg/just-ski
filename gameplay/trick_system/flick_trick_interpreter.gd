class_name FlickTrickInterpreter
extends RefCounted

enum Context { GROUND, AIR, GRIND, BAIL }

var profile: FlickTrickProfile
var _command := TrickCommand.new()
var _last_context := Context.BAIL
var _setup_active := false
var _setup_time := 0.0
var _gesture_armed := true
var _cooldown_remaining := 0.0
var _left_grab_armed := true
var _right_grab_armed := true
var _left_grab_active := false
var _right_grab_active := false

func _init(value: FlickTrickProfile = null) -> void:
	profile = value if value != null else preload("res://resources/physics/default_flick_trick_profile.tres")

func step(sample: TrickInputSample, context: int, delta: float) -> TrickCommand:
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
	_setup_active = false
	_setup_time = 0.0
	_gesture_armed = true
	_cooldown_remaining = 0.0
	_left_grab_armed = true
	_right_grab_armed = true
	_left_grab_active = false
	_right_grab_active = false
	_last_context = Context.BAIL
	_command.reset()

func _enter_context(sample: TrickInputSample, context: int) -> void:
	_setup_active = false
	_setup_time = 0.0
	_gesture_armed = sample.right_stick.length() <= profile.center_reset_threshold
	if context == Context.AIR:
		# A trigger used for braking or tucking must be released after takeoff.
		_left_grab_armed = sample.left_trigger < profile.trigger_press_threshold
		_right_grab_armed = sample.right_trigger < profile.trigger_press_threshold
		_left_grab_active = false
		_right_grab_active = false
	elif context == Context.GROUND:
		_left_grab_active = false
		_right_grab_active = false

func _step_ground(sample: TrickInputSample, delta: float, rail: bool) -> void:
	var stick := sample.right_stick
	if stick.y >= profile.setup_threshold:
		_setup_active = true
		_setup_time = 0.0
		_gesture_armed = false
		_command.phase = TrickCommand.PresentationPhase.SETUP
		_command.gesture_strength = clampf(stick.length(), 0.0, 1.0)
		return
	if not _setup_active:
		if stick.length() <= profile.center_reset_threshold and _cooldown_remaining <= 0.0:
			_gesture_armed = true
		return
	_setup_time += delta
	if _setup_time > profile.maximum_gesture_duration + profile.input_buffer_seconds:
		_setup_active = false
		return
	if stick.length() < profile.flick_threshold:
		return
	var kind := _classify_takeoff(stick, rail)
	if kind == TrickCommand.Kind.NONE:
		return
	_commit(kind, stick, true)

func _step_air(sample: TrickInputSample) -> void:
	var stick := sample.right_stick
	if stick.length() <= profile.center_reset_threshold:
		if _cooldown_remaining <= 0.0:
			_gesture_armed = true
		return
	if not _gesture_armed or _cooldown_remaining > 0.0 or stick.length() < profile.flick_threshold:
		return
	_commit(_classify_air(stick), stick, false)

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
	_commit(TrickCommand.Kind.RAIL_SLIDE_LEFT if stick.x < 0.0 else TrickCommand.Kind.RAIL_SLIDE_RIGHT, stick, false)

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

func _commit(kind: int, stick: Vector2, includes_pop: bool) -> void:
	_command.kind = kind
	_command.phase = TrickCommand.PresentationPhase.RELEASE if includes_pop else TrickCommand.PresentationPhase.ROTATE
	_command.gesture_strength = clampf(stick.length(), 0.0, 1.0)
	_command.pop_strength = lerpf(profile.minimum_command_strength, 1.0, _command.gesture_strength) if includes_pop else 0.0
	_command.rotation_impulse = _rotation_impulse(kind, _command.gesture_strength)
	_command.committed = true
	_setup_active = false
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
