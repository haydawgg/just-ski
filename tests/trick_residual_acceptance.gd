extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_spin_credit_threshold()
	_test_signed_spin_residual()
	_test_mirrored_spin_residual()
	_test_flip_credit_threshold()
	_test_cork_residual()
	_test_residual_penalizes_landing_quality()
	if failures.is_empty():
		print("TRICK_RESIDUAL_PASS: qualification, signed residuals, mirroring, and quality penalties passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("TRICK_RESIDUAL_FAIL: " + failure)
		get_tree().quit(1)

func _test_spin_credit_threshold() -> void:
	var tricks := _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	_apply_degrees(tricks, Vector3.UP, -140.0)
	if tricks.rotation_target_degrees() != 0:
		failures.append("A 140-degree spin was incorrectly credited as a completed 180")
	if tricks.current_name() != "Straight Air":
		failures.append("Underrotated 140-degree spin produced a finalized trick name")
	tricks.queue_free()

	tricks = _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	_apply_degrees(tricks, Vector3.UP, -160.0)
	if tricks.rotation_target_degrees() != 180:
		failures.append("A 160-degree spin inside the qualification tolerance did not credit 180")
	if absf(tricks.rotation_residual_degrees() + 20.0) > 0.1:
		failures.append("Underrotated 180 did not report a negative residual")
	tricks.queue_free()

func _test_signed_spin_residual() -> void:
	var tricks := _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	_apply_degrees(tricks, Vector3.UP, -350.0)
	if tricks.rotation_target_degrees() != 360:
		failures.append("A near-complete 350-degree spin did not credit 360")
	if absf(tricks.rotation_residual_degrees() + 10.0) > 0.1:
		failures.append("Underrotated 360 residual was not approximately -10 degrees")
	if absf(rad_to_deg(tricks.rotation_residual_vector().y) - 10.0) > 0.1:
		failures.append("Left underrotation did not expose the positive corrective residual direction")
	tricks.queue_free()

	tricks = _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	_apply_degrees(tricks, Vector3.UP, -391.0)
	if tricks.rotation_target_degrees() != 360:
		failures.append("A 391-degree spin did not remain credited as 360")
	if absf(tricks.rotation_residual_degrees() - 31.0) > 0.1:
		failures.append("Overrotated 360 residual was not approximately +31 degrees")
	if absf(rad_to_deg(tricks.rotation_residual_vector().y) + 31.0) > 0.1:
		failures.append("Left overrotation did not expose the negative corrective residual direction")
	tricks.queue_free()

func _test_mirrored_spin_residual() -> void:
	var left := _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	var right := _new_tricks(TrickCommand.Kind.SPIN_RIGHT)
	_apply_degrees(left, Vector3.UP, -347.0)
	_apply_degrees(right, Vector3.UP, 347.0)
	if left.rotation_target_degrees() != right.rotation_target_degrees():
		failures.append("Mirrored spins did not receive the same credited target")
	if absf(left.rotation_residual_degrees() - right.rotation_residual_degrees()) > 0.1:
		failures.append("Mirrored spins did not report matching under/over residuals")
	if left.rotation_residual_vector().y * right.rotation_residual_vector().y >= 0.0:
		failures.append("Mirrored spins did not expose mirrored corrective residual directions")
	left.queue_free()
	right.queue_free()

func _test_flip_credit_threshold() -> void:
	var tricks := _new_tricks(TrickCommand.Kind.FRONTFLIP)
	_apply_degrees(tricks, Vector3.RIGHT, 300.0)
	if tricks.rotation_target_degrees() != 0:
		failures.append("A 300-degree flip was credited before entering the completion tolerance")
	tricks.queue_free()

	tricks = _new_tricks(TrickCommand.Kind.FRONTFLIP)
	_apply_degrees(tricks, Vector3.RIGHT, 330.0)
	if tricks.rotation_target_degrees() != 360:
		failures.append("A 330-degree flip inside the completion tolerance did not credit 360")
	if absf(tricks.rotation_residual_degrees() + 30.0) > 0.1:
		failures.append("Frontflip residual did not preserve the underrotation sign")
	tricks.queue_free()

func _test_cork_residual() -> void:
	var tricks := _new_tricks(TrickCommand.Kind.CORK_LEFT)
	var radians := deg_to_rad(345.0)
	tricks.update_air(Vector3(0.0, -1.0, -1.0).normalized() * radians, 1.0)
	if tricks.rotation_target_degrees() != 360:
		failures.append("Near-complete cork did not credit the expected 360 bucket")
	if absf(tricks.rotation_residual_degrees() + 15.0) > 0.1:
		failures.append("Cork residual did not report the expected underrotation")
	tricks.queue_free()

func _test_residual_penalizes_landing_quality() -> void:
	var clean_quality := [0.0]
	var over_quality := [0.0]

	var clean := _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	clean.trick_landed.connect(func(_name: String, _points: int, quality: float) -> void: clean_quality[0] = quality)
	_apply_degrees(clean, Vector3.UP, -180.0)
	clean.land(1.0, false)

	var over := _new_tricks(TrickCommand.Kind.SPIN_LEFT)
	over.trick_landed.connect(func(_name: String, _points: int, quality: float) -> void: over_quality[0] = quality)
	_apply_degrees(over, Vector3.UP, -243.0)
	over.land(1.0, false)

	if clean_quality[0] < 0.99:
		failures.append("Exact completed spin unexpectedly lost landing quality")
	if over_quality[0] >= clean_quality[0]:
		failures.append("Large overrotation residual did not reduce scored landing quality")

func _new_tricks(kind: int) -> TrickController:
	var tricks := TrickController.new()
	add_child(tricks)
	tricks.begin_air(false, kind)
	return tricks

func _apply_degrees(tricks: TrickController, axis: Vector3, degrees: float) -> void:
	tricks.update_air(axis * deg_to_rad(degrees), 1.0)
