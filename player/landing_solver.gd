class_name LandingSolver
extends RefCounted

enum Outcome { CLEAN, SKETCHY, HARD, BAIL }
enum FailureReason { NONE, UPRIGHT, IMPACT, ANGULAR }

static func evaluate(up: Vector3, forward: Vector3, normal: Vector3, velocity: Vector3, angular_velocity: Vector3, profile: SkiPhysicsProfile) -> Dictionary:
	var safe_normal := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var safe_up := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var safe_forward := forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var tangent_velocity := velocity.slide(safe_normal)
	var travel := tangent_velocity.normalized() if tangent_velocity.length() > 0.5 else safe_forward
	var projected_forward := safe_forward.slide(safe_normal)
	if projected_forward.length_squared() < 0.0001:
		projected_forward = travel
	var aligned_forward := absf(projected_forward.normalized().dot(travel))
	var upright_dot := clampf(safe_up.dot(safe_normal), -1.0, 1.0)
	var upright := clampf((upright_dot + 0.15) / 1.15, 0.0, 1.0)
	var impact := maxf(0.0, -velocity.dot(safe_normal))
	var impact_score := 1.0 - clampf(impact / profile.bail_impact_speed, 0.0, 1.0)
	var angular_ratio := angular_velocity.length() / maxf(profile.maximum_angular_speed, 0.01)
	var spin_score := 1.0 - clampf(angular_ratio, 0.0, 1.0)
	var score := (
		aligned_forward * profile.landing_alignment_weight
		+ upright * profile.landing_upright_weight
		+ impact_score * profile.landing_impact_weight
		+ spin_score * profile.landing_angular_weight
	)
	var outcome := Outcome.BAIL
	var failure_reason := FailureReason.NONE
	if upright_dot < profile.recoverable_upright_dot:
		failure_reason = FailureReason.UPRIGHT
	elif impact >= profile.bail_impact_speed:
		failure_reason = FailureReason.IMPACT
	elif angular_ratio >= profile.bail_angular_ratio:
		failure_reason = FailureReason.ANGULAR
	var hard_failure := (
		upright_dot < profile.recoverable_upright_dot
		or impact >= profile.bail_impact_speed
		or angular_ratio >= profile.bail_angular_ratio
	)
	if not hard_failure and score >= profile.clean_threshold and upright_dot >= profile.clean_upright_dot and impact <= profile.bail_impact_speed * profile.clean_impact_ratio:
		outcome = Outcome.CLEAN
	elif not hard_failure and score >= profile.sketchy_threshold and upright_dot >= profile.sketchy_upright_dot and impact <= profile.bail_impact_speed * profile.sketchy_impact_ratio:
		outcome = Outcome.SKETCHY
	elif not hard_failure:
		outcome = Outcome.HARD
	var lateral_velocity := velocity.dot(safe_forward.cross(safe_normal).normalized()) if safe_forward.cross(safe_normal).length_squared() > 0.0001 else 0.0
	var forward_velocity := velocity.dot(projected_forward.normalized()) if projected_forward.length_squared() > 0.0001 else 0.0
	var ski_alignment_error := 1.0 - aligned_forward
	var body_roll_error := 1.0 - upright
	var body_pitch_error := clampf(1.0 - absf(safe_forward.dot(projected_forward.normalized() if projected_forward.length_squared() > 0.0001 else travel)), 0.0, 1.0)
	var flatness := clampf(safe_normal.dot(Vector3.UP), 0.0, 1.0)
	var flat_bias := smoothstep(profile.landing_flat_surface_bias_start, profile.landing_flat_surface_bias_end, flatness) * profile.landing_flat_surface_bias_weight
	var impact_severity := clampf(
		impact / maxf(profile.bail_impact_speed, 0.01) * profile.landing_impact_severity_scale
		+ body_roll_error * profile.landing_impact_body_roll_weight
		+ flat_bias,
		0.0,
		1.0
	)
	var balance_error := clampf(
		ski_alignment_error * profile.landing_balance_alignment_weight
		+ body_roll_error * profile.landing_balance_upright_weight
		+ clampf(angular_ratio, 0.0, 1.0) * profile.landing_balance_angular_weight
		+ clampf(absf(lateral_velocity) / maxf(profile.landing_balance_lateral_speed_reference, 0.01), 0.0, 1.0) * profile.landing_balance_lateral_weight,
		0.0,
		1.0
	)
	return {
		"score": score,
		"outcome": outcome,
		"failure_reason": failure_reason,
		"impact": impact,
		"impact_severity": impact_severity,
		"balance_error": balance_error,
		"ski_alignment_error": ski_alignment_error,
		"body_roll_error": body_roll_error,
		"body_pitch_error": body_pitch_error,
		"alignment": aligned_forward,
		"upright": upright,
		"upright_dot": upright_dot,
		"angular_ratio": angular_ratio,
		"lateral_velocity": lateral_velocity,
		"forward_velocity": forward_velocity,
		"hard_failure": hard_failure,
	}
