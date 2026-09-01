class_name RotationIntentAuthor
extends RefCounted

var profile: FlickTrickProfile

func _init(value: FlickTrickProfile) -> void:
	profile = value

## Converts one completed preload gesture into a continuous local-space angular
## impulse. Classification is descriptive only and never changes the impulse.
func author_takeoff(sample: TrickInputSample, setup_quality: float) -> RotationIntent:
	var release := sample.right_stick
	var lateral := _signed_deadzone(release.x, profile.continuous_axis_deadzone)
	var vertical_release := clampf(-release.y, 0.0, 1.0)
	var pitch_signal := _signed_deadzone(-sample.left_stick.y, profile.flip_takeoff_pressure_threshold)
	var roll_signal := lateral * vertical_release

	# Preserve subtle edge/release coupling near the cardinal regions without
	# introducing a sector boundary into the physical axis.
	var pitch_impulse := pitch_signal * profile.flip_impulse
	var flat_spin_weight := 1.0 - smoothstep(
		profile.continuous_cork_signal_threshold * 0.75,
		profile.continuous_cork_signal_threshold * 1.25,
		absf(roll_signal)
	)
	pitch_impulse += vertical_release * absf(lateral) * profile.spin_pitch_coupling_impulse * flat_spin_weight
	var yaw_impulse := lateral * profile.spin_impulse
	yaw_impulse += -sample.left_stick.x * absf(pitch_signal) * profile.flip_yaw_coupling_impulse
	var roll_impulse := roll_signal * profile.cork_roll_impulse
	roll_impulse += sample.left_stick.x * absf(lateral) * profile.spin_roll_coupling_impulse
	roll_impulse += release.x * absf(pitch_signal) * profile.flip_roll_coupling_impulse

	var weighted_axis := Vector3(pitch_impulse, yaw_impulse, roll_impulse)
	if weighted_axis.length_squared() <= 0.0001:
		return RotationIntent.new()
	var strength := lerpf(profile.minimum_command_strength, 1.0, clampf(setup_quality, 0.0, 1.0))
	var magnitude := _continuous_magnitude(pitch_signal, lateral, roll_signal) * strength
	var impulse := weighted_axis.normalized() * magnitude
	return RotationIntent.new().configure(impulse, setup_quality, presentation_kind(impulse.normalized()))

func presentation_kind(axis_local: Vector3) -> int:
	if axis_local.length_squared() <= 0.0001:
		return TrickCommand.Kind.NONE
	var weights := _axis_weights(axis_local)
	if weights.z >= profile.continuous_cork_presentation_weight and weights.y > profile.continuous_axis_deadzone:
		return TrickCommand.Kind.CORK_LEFT if axis_local.y < 0.0 else TrickCommand.Kind.CORK_RIGHT
	if weights.x >= weights.y:
		return TrickCommand.Kind.FRONTFLIP if axis_local.x > 0.0 else TrickCommand.Kind.BACKFLIP
	return TrickCommand.Kind.SPIN_LEFT if axis_local.y < 0.0 else TrickCommand.Kind.SPIN_RIGHT

func _continuous_magnitude(pitch: float, yaw: float, roll: float) -> float:
	var pitch_weight := absf(pitch)
	var yaw_weight := absf(yaw)
	var roll_weight := absf(roll)
	var total := pitch_weight + yaw_weight + roll_weight
	if total <= 0.0001:
		return 0.0
	var cork_reference := Vector2(profile.cork_yaw_impulse, profile.cork_roll_impulse).length()
	return (
		pitch_weight * profile.flip_impulse
		+ yaw_weight * profile.spin_impulse
		+ roll_weight * cork_reference
	) / total

func _axis_weights(axis: Vector3) -> Vector3:
	var absolute := Vector3(absf(axis.x), absf(axis.y), absf(axis.z))
	var total := absolute.x + absolute.y + absolute.z
	return absolute / total if total > 0.0001 else Vector3.ZERO

func _signed_deadzone(value: float, deadzone: float) -> float:
	var amount := absf(value)
	if amount <= deadzone:
		return 0.0
	return signf(value) * (amount - deadzone) / maxf(1.0 - deadzone, 0.001)
