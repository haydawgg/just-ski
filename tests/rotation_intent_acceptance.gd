extends Node

var failures: Array[String] = []
var profile := FlickTrickProfile.new()
var author := RotationIntentAuthor.new(profile)

func _ready() -> void:
	_test_cardinal_compatibility()
	_test_axis_continuity()
	_test_mirror_symmetry()
	_test_energy_is_direction_independent()
	_test_blended_axis()
	_test_presentation_uses_full_axis()
	if failures.is_empty():
		print("ROTATION_INTENT_PASS: continuous takeoff axes are compatible, smooth, symmetric, and energy-bounded")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ROTATION_INTENT_FAIL: " + failure)
		get_tree().quit(1)

func _test_cardinal_compatibility() -> void:
	var neutral := _intent(Vector2.UP, Vector2.ZERO)
	if neutral.committed:
		failures.append("Neutral vertical pop unexpectedly authored rotation")
	var spin := _intent(Vector2.LEFT, Vector2.ZERO)
	if spin.presentation_kind != TrickCommand.Kind.SPIN_LEFT or spin.axis_local.y >= -0.99:
		failures.append("Canonical left spin did not remain yaw-dominant")
	var front := _intent(Vector2.UP, Vector2(0.0, -1.0))
	if front.presentation_kind != TrickCommand.Kind.FRONTFLIP or front.axis_local.x <= 0.99:
		failures.append("Canonical frontflip did not remain pitch-dominant")

func _test_axis_continuity() -> void:
	var previous := _intent(Vector2(-0.9, -0.35).normalized(), Vector2.ZERO).axis_local
	for index: int in range(1, 12):
		var y := lerpf(-0.35, -0.85, float(index) / 11.0)
		var current := _intent(Vector2(-0.9, y).normalized(), Vector2.ZERO).axis_local
		if rad_to_deg(previous.angle_to(current)) > 9.0:
			failures.append("A small gesture-angle change caused a discontinuous physical axis jump")
			return
		previous = current

func _test_mirror_symmetry() -> void:
	var left := _intent(Vector2(-0.75, -0.7).normalized(), Vector2.ZERO)
	var right := _intent(Vector2(0.75, -0.7).normalized(), Vector2.ZERO)
	if left.impulse_local.distance_to(-right.impulse_local) > 0.02:
		failures.append("Mirrored off-axis releases did not produce mirrored impulses")

func _test_energy_is_direction_independent() -> void:
	var spin := _intent(Vector2.LEFT, Vector2.ZERO).magnitude
	var cork := _intent(Vector2(-0.75, -0.7).normalized(), Vector2.ZERO).magnitude
	var flip := _intent(Vector2.UP, Vector2(0.0, -1.0)).magnitude
	if maxf(spin, maxf(cork, flip)) - minf(spin, minf(cork, flip)) > 0.65:
		failures.append("Changing the authored axis changed the takeoff energy budget too much")

func _test_blended_axis() -> void:
	var blended := _intent(Vector2(-0.72, -0.68).normalized(), Vector2(-0.45, -0.9))
	if not blended.committed or minf(absf(blended.axis_local.x), minf(absf(blended.axis_local.y), absf(blended.axis_local.z))) <= 0.01:
		failures.append("Blended pressure, edge, and release input did not author a full three-axis intent")

func _test_presentation_uses_full_axis() -> void:
	var classifier := TrickPresentationClassifier.new()
	var cork_axis := Vector3(0.0, -1.0, -1.0).normalized()
	if classifier.classify(cork_axis) != TrickCommand.Kind.CORK_LEFT:
		failures.append("Presentation did not derive a left cork label from the continuous axis")
	var accumulated := cork_axis * deg_to_rad(345.0)
	if classifier.target_degrees(cork_axis, accumulated, TrickCommand.Kind.NONE) != 360:
		failures.append("Presentation did not credit full-axis cork progress")
	if absf(classifier.residual_degrees(cork_axis, accumulated, TrickCommand.Kind.NONE) + 15.0) > 0.1:
		failures.append("Presentation residual did not use progress along the committed axis")

func _intent(release: Vector2, left_stick: Vector2) -> RotationIntent:
	var sample := TrickInputSample.new()
	sample.right_stick = release
	sample.left_stick = left_stick
	return author.author_takeoff(sample, 1.0)
