class_name AirTrickPoseLayer
extends RefCounted

## Computes airborne phase state without touching scene nodes. The coordinator
## copies the resulting values into its public/debug presentation state.

var air_size := 0.0
var air_takeoff_weight := 0.0
var air_early_weight := 0.0
var air_apex_weight := 0.0
var air_descent_weight := 0.0
var air_flex := 0.0
var air_phase_name := "Ground"

func update_jump_animation(frame: SkierAnimationFrame, delta: float, profile: SkierAnimationProfile) -> void:
	if frame.locomotion_state != 1:
		air_size = _damp(air_size, 0.0, profile.air_phase_response, delta)
		air_takeoff_weight = _damp(air_takeoff_weight, 0.0, profile.air_phase_response, delta)
		air_early_weight = _damp(air_early_weight, 0.0, profile.air_phase_response, delta)
		air_apex_weight = _damp(air_apex_weight, 0.0, profile.air_phase_response, delta)
		air_descent_weight = _damp(air_descent_weight, 0.0, profile.air_phase_response, delta)
		air_flex = _damp(air_flex, 0.0, profile.air_phase_response, delta)
		air_phase_name = "Ground"
		return
	var takeoff_size := smoothstep(
		minf(profile.air_small_takeoff_speed, profile.air_large_takeoff_speed),
		maxf(profile.air_small_takeoff_speed, profile.air_large_takeoff_speed),
		frame.takeoff_upward_speed
	)
	if frame.takeoff_type == SkierAnimationFrame.TakeoffType.CHARGED_POP:
		takeoff_size = maxf(takeoff_size, frame.takeoff_charge)
	elif frame.takeoff_type == SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF:
		takeoff_size *= 0.82
	air_size = _damp(air_size, clampf(takeoff_size, 0.0, 1.0), profile.air_phase_response, delta)
	var hold_time := maxf(profile.air_takeoff_hold_time, 0.02) * lerpf(0.65, 1.15, air_size)
	var takeoff_target := 1.0 - smoothstep(0.0, hold_time, frame.air_time)
	if frame.takeoff_type == SkierAnimationFrame.TakeoffType.TERRAIN_TAKEOFF:
		takeoff_target *= lerpf(0.55, 0.82, air_size)
	var apex_band := maxf(profile.air_apex_velocity_band, 0.05)
	var ascent_reference := maxf(frame.takeoff_upward_speed * 0.82, apex_band * 1.5)
	var early_target := (1.0 - takeoff_target) * smoothstep(apex_band * 0.35, ascent_reference, frame.air_upward_velocity)
	var apex_target := (1.0 - takeoff_target) * (1.0 - smoothstep(apex_band * 0.28, apex_band * 1.35, absf(frame.air_upward_velocity)))
	var descent_target := (1.0 - takeoff_target) * smoothstep(
		apex_band * 0.25,
		maxf(profile.air_descent_velocity_reference, apex_band),
		-frame.air_upward_velocity
	)
	if frame.predicted_landing_time >= 0.0:
		var proximity := 1.0 - smoothstep(0.12, maxf(profile.landing_anticipation_time, 0.13), frame.predicted_landing_time)
		descent_target = maxf(descent_target, proximity * (1.0 - takeoff_target))
	air_takeoff_weight = _damp(air_takeoff_weight, takeoff_target, profile.air_phase_response, delta)
	air_early_weight = _damp(air_early_weight, early_target, profile.air_phase_response, delta)
	air_apex_weight = _damp(air_apex_weight, apex_target, profile.air_phase_response, delta)
	air_descent_weight = _damp(air_descent_weight, descent_target, profile.air_phase_response, delta)
	if air_takeoff_weight > 0.42:
		air_phase_name = "Takeoff"
	elif air_descent_weight > 0.28:
		air_phase_name = "Descent"
	elif air_apex_weight > 0.32:
		air_phase_name = "Apex"
	else:
		air_phase_name = "Early Air"

func reset() -> void:
	air_size = 0.0
	air_takeoff_weight = 0.0
	air_early_weight = 0.0
	air_apex_weight = 0.0
	air_descent_weight = 0.0
	air_flex = 0.0
	air_phase_name = "Ground"

func _damp(current: float, target: float, response: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-response * delta))
