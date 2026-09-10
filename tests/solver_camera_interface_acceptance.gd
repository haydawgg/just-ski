extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_camera_interfaces()
	AudioManager.shutdown_audio()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("SOLVER_CAMERA_INTERFACE_PASS: projection, composition, framing, and collision interfaces passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SOLVER_CAMERA_INTERFACE_FAIL: " + failure)
	get_tree().quit(1)

func _test_camera_interfaces() -> void:
	var projection := CompositionEvaluator.project_point(Vector3(0.0, 2.0, 5.0), Basis.IDENTITY, 68.0, Vector2(1920.0, 1080.0), Vector3.ZERO)
	if not (projection.get("screen", Vector2.ZERO) as Vector2).is_finite():
		failures.append("Composition evaluator returned a non-finite projection")
	var evaluation := {"hard_violation": 0.0, "body_occlusion": 0.0}
	if not CompositionEvaluator.hard_valid(evaluation, 0.25):
		failures.append("Composition evaluator rejected a valid hard pose")
	var projected_points: Array[Dictionary] = []
	projected_points.append({"screen": Vector2(0.5, 0.5), "depth": 4.0})
	projected_points.append({"screen": Vector2(0.6, 0.55), "depth": 5.0})
	var landmark_evaluation := CompositionEvaluator.evaluate_landmarks(
		projected_points,
		0,
		projected_points.size(),
		Rect2(0.0, 0.0, 1.0, 1.0),
		Rect2(0.1, 0.1, 0.8, 0.8)
	)
	if float(landmark_evaluation.get("average_depth", 0.0)) <= 0.0 or float(landmark_evaluation.get("hard_violation", INF)) != 0.0:
		failures.append("Composition evaluator did not preserve valid landmark bounds")
	var behind_points: Array[Dictionary] = []
	behind_points.append({"screen": Vector2(0.5, 0.5), "depth": -1.0})
	var behind_evaluation := CompositionEvaluator.evaluate_landmarks(
		behind_points,
		0,
		behind_points.size(),
		Rect2(0.0, 0.0, 1.0, 1.0),
		Rect2(0.1, 0.1, 0.8, 0.8)
	)
	if float(behind_evaluation.get("hard_violation", 0.0)) != INF:
		failures.append("Composition evaluator did not hard-fail a behind-camera landmark")
	var framing := CameraFramingSolver.new()
	framing.configure(0.5, 1.15, 3.4, 9.0, 20.0)
	framing.reset(0.0, true)
	if not framing.step_air(Vector3(0.0, 1.0, 0.0), Vector3.UP, 1.0 / 60.0, 0.2).is_finite():
		failures.append("Camera framing solver returned a non-finite target")
	var collision := CameraCollisionSolver.new()
	collision.configure(null, null, 1 | 4, 0.22, 0.35)
	if not bool(collision.destination_is_clear(Vector3.ZERO)):
		failures.append("Camera collision solver did not treat an unbound world as clear")
	if collision.foreground_occluded(Vector3.ZERO, Vector3.FORWARD, 0.12):
		failures.append("Camera collision solver reported foreground occlusion without a bound world")
