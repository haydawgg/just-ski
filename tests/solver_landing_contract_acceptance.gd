extends Node

const ANIMATION_PROFILE := preload("res://resources/animation/default_animation_profile.tres")

var failures: Array[String] = []

func _ready() -> void:
	_test_landing_extension_contracts()
	AudioManager.shutdown_audio()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("SOLVER_LANDING_CONTRACT_PASS: extension, stance, preview, and obstruction contracts passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_LANDING_CONTRACT_FAIL: " + failure)
	get_tree().quit(1)

func _test_landing_extension_contracts() -> void:
	var landing := LandingPoseLayer.new()
	if absf(landing.air_extension_scale(2.0, 2.0, 0.54) - 1.0) > 0.001:
		failures.append("Extension restraint altered the reach without snow readings")
	if absf(landing.air_extension_scale(1.0, 1.0, 0.54) - 1.0) > 0.001:
		failures.append("Extension restraint altered the reach far above the seat")
	var near_scale := landing.air_extension_scale(0.64, 0.64, 0.54)
	if near_scale < 0.25 or near_scale > 0.45:
		failures.append("Extension restraint did not scale the reach at 0.10 m seat gap (%.3f)" % near_scale)
	if absf(landing.air_extension_scale(0.5, 0.5, 0.54) - 0.15) > 0.001:
		failures.append("Extension restraint did not hold its minimum at seat penetration")
	var asymmetric := landing.air_extension_scale(2.0, 0.60, 0.54)
	if asymmetric < 0.15 or asymmetric > 0.3:
		failures.append("Extension restraint ignored the nearer ski probe (%.3f)" % asymmetric)

	var crossed: Array = SkiConstrainedLegIK.separate_boot_targets(Vector3(0.2, 0.0, 0.0), Vector3(-0.2, 0.0, 0.0), Basis.IDENTITY, 0.16)
	if float((crossed[1] as Vector3 - crossed[0] as Vector3).x) < 0.159:
		failures.append("Boot stance separation did not restore the minimum ski stance")
	var ordered: Array = SkiConstrainedLegIK.separate_boot_targets(Vector3(-0.3, 0.0, 0.0), Vector3(0.3, 0.0, 0.0), Basis.IDENTITY, 0.16)
	if (ordered[0] as Vector3).distance_to(Vector3(-0.3, 0.0, 0.0)) > 0.001 or (ordered[1] as Vector3).distance_to(Vector3(0.3, 0.0, 0.0)) > 0.001:
		failures.append("Boot stance separation moved an already valid stance")
	var degenerate := SkiConstrainedLegIK.contact_transform(Vector3.ZERO, Vector3.UP, Vector3.UP)
	if not SkiConstrainedLegIK.is_finite_transform(degenerate):
		failures.append("Shared ski-contact helper produced a non-finite degenerate heading frame")
	var slope_normal := Vector3(0.0, 0.8, 0.6).normalized()
	var stance: Dictionary = SkiConstrainedLegIK.stance_ski_targets(Vector3.ZERO, Vector3.FORWARD, slope_normal, 0.22)
	if not bool(stance.valid):
		failures.append("Shared stance helper rejected a sloped landing frame")
	elif absf((stance.forward as Vector3).dot(slope_normal)) > 0.02:
		failures.append("Shared stance helper did not keep ski forward tangent to the support plane")

	var preview_frame := SkierAnimationFrame.new()
	preview_frame.locomotion_state = 1
	preview_frame.predicted_landing_valid = true
	preview_frame.predicted_landing_time = 0.12
	preview_frame.predicted_landing_point = Vector3.ZERO
	preview_frame.predicted_landing_normal = Vector3.UP
	preview_frame.ski_forward = Vector3.FORWARD
	preview_frame.ski_forward_valid = true
	preview_frame.velocity_heading = Vector3.FORWARD
	if not LandingPoseLayer.preview_window_active(preview_frame, ANIMATION_PROFILE):
		failures.append("Landing preview window rejected a valid near-contact prediction")
	preview_frame.predicted_landing_time = ANIMATION_PROFILE.landing_anticipation_time + 0.2
	if LandingPoseLayer.preview_window_active(preview_frame, ANIMATION_PROFILE):
		failures.append("Landing preview window accepted a prediction outside anticipation")
	if absf(LandingPoseLayer.preview_ik_weight(0.8, 0.5, 0.5, 1.0) - 0.2) > 0.0001:
		failures.append("AIR preview weight is not preview × anticipation × extension clearance")
	if LandingPoseLayer.preview_ik_weight(1.0, 1.0, 1.0, 0.0) != 0.0:
		failures.append("AIR preview weight ignored a feature-obstruction veto")
	if SkiConstrainedLegIK.feature_obstruction_scale(null, Vector3.UP, Vector3.DOWN) != 1.0:
		failures.append("Feature obstruction veto did not no-op without a physics space")
