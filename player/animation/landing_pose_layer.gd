class_name LandingPoseLayer
extends RefCounted

## Landing readiness is a sampled-data policy and is intentionally independent
## of the coordinator's joint-target application.

func score_error(error: float, good: float, bad: float) -> float:
	if not is_finite(error) or not is_finite(good) or not is_finite(bad):
		return 0.0
	var good_limit := maxf(good, 0.0)
	var bad_limit := maxf(bad, good_limit + 0.001)
	return 1.0 - smoothstep(good_limit, bad_limit, absf(error))

func readiness_targets(frame: SkierAnimationFrame, profile: SkierAnimationProfile) -> Dictionary:
	var empty := {
		"valid": false,
		"inputs_valid": false,
		"heading": 0.0,
		"pitch": 0.0,
		"spin": 0.0,
		"upright": 0.0,
		"residual": 0.0,
		"projected_heading_error": 0.0,
		"projected_residual": 0.0,
	}
	if frame.locomotion_state != 1 or not frame.predicted_landing_valid or not is_finite(frame.predicted_landing_time) or frame.predicted_landing_time < 0.0:
		return empty
	var landing_normal := frame.predicted_landing_normal
	if not _finite_vector(landing_normal) or landing_normal.length_squared() <= 0.000001:
		return empty
	landing_normal = landing_normal.normalized()
	var time_to_contact := clampf(frame.predicted_landing_time, 0.0, 2.0)
	var body_up_valid := frame.body_up_valid and _finite_vector(frame.body_up) and frame.body_up.length_squared() > 0.000001
	var ski_forward_valid := frame.ski_forward_valid and _finite_vector(frame.ski_forward) and frame.ski_forward.length_squared() > 0.000001
	var ski_up_valid := frame.ski_up_valid and _finite_vector(frame.ski_up) and frame.ski_up.length_squared() > 0.000001
	var desired_heading_valid := _finite_vector(frame.velocity_heading) and frame.velocity_heading.length_squared() > 0.000001
	var local_angular_valid := _finite_vector(frame.angular_velocity)
	var world_angular_valid := frame.angular_velocity_world_valid and _finite_vector(frame.angular_velocity_world)
	var residual_valid := _finite_vector(frame.rotation_residual)
	var heading_valid := ski_forward_valid and desired_heading_valid and world_angular_valid
	var pitch_valid := ski_forward_valid and ski_up_valid
	var upright_valid := body_up_valid
	var spin_valid := local_angular_valid
	var maneuver_residual_valid := local_angular_valid and residual_valid
	var ski_forward := frame.ski_forward.normalized() if ski_forward_valid else Vector3.FORWARD
	var body_up := frame.body_up.normalized() if body_up_valid else Vector3.UP
	var heading := ski_forward.slide(landing_normal)
	var desired_heading := frame.velocity_heading.slide(landing_normal)
	var heading_error := 0.0
	if heading_valid and heading.length_squared() > 0.000001 and desired_heading.length_squared() > 0.000001:
		heading_error = heading.normalized().signed_angle_to(desired_heading.normalized(), landing_normal)
	else:
		heading_valid = false
	var projected_heading_error := 0.0
	if heading_valid and is_finite(heading_error):
		var yaw_rate_about_landing := frame.angular_velocity_world.dot(landing_normal)
		projected_heading_error = wrapf(heading_error + yaw_rate_about_landing * time_to_contact, -PI, PI)
	else:
		heading_valid = false
	var pitch_error := 0.0
	if pitch_valid:
		var ski_forward_plane := ski_forward.slide(landing_normal)
		if ski_forward_plane.length_squared() > 0.000001:
			pitch_error = absf(atan2(ski_forward.dot(landing_normal), ski_forward_plane.length()))
		else:
			pitch_valid = false
	var spin_error := frame.angular_velocity.length() if spin_valid else NAN
	var upright_error := acos(clampf(body_up.dot(landing_normal), -1.0, 1.0)) if upright_valid else NAN
	var projected_residual := 0.0
	if maneuver_residual_valid:
		var projected_residual_vector := Vector3(
			wrapf(frame.rotation_residual.x + frame.angular_velocity.x * time_to_contact, -PI, PI),
			wrapf(frame.rotation_residual.y + frame.angular_velocity.y * time_to_contact, -PI, PI),
			wrapf(frame.rotation_residual.z + frame.angular_velocity.z * time_to_contact, -PI, PI)
		)
		if _finite_vector(projected_residual_vector):
			projected_residual = maxf(absf(projected_residual_vector.x), maxf(absf(projected_residual_vector.y), absf(projected_residual_vector.z)))
		else:
			maneuver_residual_valid = false
	var inputs_valid := heading_valid and pitch_valid and spin_valid and upright_valid and maneuver_residual_valid
	return {
		"valid": true,
		"inputs_valid": inputs_valid,
		"heading": score_error(projected_heading_error, profile.landing_readiness_heading_good, profile.landing_readiness_heading_bad) if heading_valid else 0.0,
		"pitch": score_error(pitch_error, profile.landing_readiness_pitch_good, profile.landing_readiness_pitch_bad) if pitch_valid else 0.0,
		"spin": score_error(spin_error, profile.landing_readiness_spin_good, profile.landing_readiness_spin_bad) if spin_valid else 0.0,
		"upright": score_error(upright_error, profile.landing_readiness_upright_good, profile.landing_readiness_upright_bad) if upright_valid else 0.0,
		"residual": score_error(projected_residual, profile.landing_readiness_residual_good, profile.landing_readiness_residual_bad) if maneuver_residual_valid else 0.0,
		"projected_heading_error": projected_heading_error,
		"projected_residual": projected_residual,
	}

func ready_for_values(valid: bool, anticipation: float, readiness: float, profile: SkierAnimationProfile) -> bool:
	return valid and anticipation >= profile.ready_anticipation_threshold and readiness >= profile.ready_readiness_threshold

## Existing landing anticipation/alignment envelope. Preview IK may only
## synthesize targets inside this window.
static func preview_window(profile: SkierAnimationProfile) -> float:
	return maxf(maxf(profile.landing_anticipation_time, profile.landing_alignment_start), 0.05)

static func preview_window_active(frame: SkierAnimationFrame, profile: SkierAnimationProfile) -> bool:
	if frame.locomotion_state != 1 or frame.spawn_settle_active:
		return false
	if not frame.predicted_landing_valid or not is_finite(frame.predicted_landing_time) or frame.predicted_landing_time < 0.0:
		return false
	return frame.predicted_landing_time <= preview_window(profile)

static func preview_ik_weight(
	preview_weight: float,
	landing_anticipation: float,
	extension_clearance: float,
	obstruction_scale: float = 1.0
) -> float:
	return (
		clampf(preview_weight, 0.0, 1.0)
		* clampf(landing_anticipation, 0.0, 1.0)
		* clampf(extension_clearance, 0.0, 1.0)
		* clampf(obstruction_scale, 0.0, 1.0)
	)

## Presentation-only predicted-surface ski targets. The predicted point and
## normal define the landing plane; the current body is projected onto that
## plane so legs reach the upcoming surface rather than a distant impact point.
static func air_preview_targets(
	frame: SkierAnimationFrame,
	profile: SkierAnimationProfile,
	min_stance: float,
	body_origin: Vector3,
	body_basis: Basis = Basis.IDENTITY
) -> Dictionary:
	var empty := {
		"valid": false,
		"left": Transform3D.IDENTITY,
		"right": Transform3D.IDENTITY,
		"forward": Vector3.FORWARD,
		"up": Vector3.UP,
		"origin": Vector3.ZERO,
	}
	if not preview_window_active(frame, profile):
		return empty
	var landing_normal := frame.predicted_landing_normal
	if not landing_normal.is_finite() or landing_normal.length_squared() <= 0.000001:
		return empty
	landing_normal = landing_normal.normalized()
	if not frame.predicted_landing_point.is_finite() or not body_origin.is_finite():
		return empty
	var heading := _preview_heading(frame, landing_normal, body_basis)
	var origin := SkiConstrainedLegIK.project_onto_plane(body_origin, frame.predicted_landing_point, landing_normal)
	# The presentation stance contract holds for preview too: the symmetric
	# preview width stays inside the same visual maximum (no behavior change
	# while air_preview_stance_half_width remains below it).
	var half_stance := clampf(
		maxf(profile.air_preview_stance_half_width, min_stance * 0.5),
		0.0,
		maxf(profile.visual_stance_max_half_width, min_stance * 0.5)
	)
	var stance: Dictionary = SkiConstrainedLegIK.stance_ski_targets(origin, heading, landing_normal, half_stance)
	if not bool(stance.valid):
		return empty
	var left: Transform3D = stance.left
	var right: Transform3D = stance.right
	var separated: Array = SkiConstrainedLegIK.separate_boot_targets(
		left.origin,
		right.origin,
		stance.basis as Basis,
		min_stance
	)
	left.origin = separated[0]
	right.origin = separated[1]
	var span_separated: Array = SkiConstrainedLegIK.separate_ski_span(
		left.origin, right.origin,
		stance.forward as Vector3, stance.forward as Vector3,
		stance.lateral as Vector3, min_stance)
	left.origin = span_separated[0]
	right.origin = span_separated[1]
	if (right.origin - left.origin).dot(stance.lateral as Vector3) < min_stance - 0.0001:
		return empty
	if not SkiConstrainedLegIK.is_finite_transform(left) or not SkiConstrainedLegIK.is_finite_transform(right):
		return empty
	return {
		"valid": true,
		"left": left,
		"right": right,
		"forward": stance.forward,
		"up": stance.up,
		"origin": origin,
	}

static func _preview_heading(frame: SkierAnimationFrame, landing_normal: Vector3, body_basis: Basis) -> Vector3:
	var ski_forward := frame.ski_forward if frame.ski_forward_valid and frame.ski_forward.is_finite() else Vector3.ZERO
	var travel := frame.velocity_heading if frame.velocity_heading.is_finite() else Vector3.ZERO
	var heading := ski_forward.slide(landing_normal)
	if heading.length_squared() < 0.0001:
		heading = travel.slide(landing_normal)
	if heading.length_squared() < 0.0001:
		heading = (-body_basis.z).slide(landing_normal) if body_basis.z.is_finite() else Vector3.ZERO
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD.slide(landing_normal)
	if heading.length_squared() < 0.0001:
		heading = Vector3.RIGHT
	return heading.normalized()

## Restraint for airborne landing anticipation leg extension. The reach is
## time-driven, but the rendered skis must not punch through the support
## surface before the authoritative touchdown seats the body. Probe distances
## at or above NO_HIT_DISTANCE mean no valid snow reading and leave the reach
## untouched; near the seat the extension scales down to a held minimum.
static func air_extension_scale(left_ground_distance: float, right_ground_distance: float, seat_distance: float) -> float:
	const NO_HIT_DISTANCE := 1.5
	const FULL_REACH_GAP := 0.3
	const MIN_SCALE := 0.15
	var gap := INF
	if left_ground_distance < NO_HIT_DISTANCE:
		gap = minf(gap, left_ground_distance - seat_distance)
	if right_ground_distance < NO_HIT_DISTANCE:
		gap = minf(gap, right_ground_distance - seat_distance)
	if gap == INF:
		return 1.0
	return clampf(gap / FULL_REACH_GAP, MIN_SCALE, 1.0)

func _finite_vector(value: Vector3) -> bool:
	return value.is_finite()
