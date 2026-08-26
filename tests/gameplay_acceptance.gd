extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var frame := 0
var failures: Array[String] = []
var carve_start_x := 0.0
var speed_before_brake := 0.0
var air_seen := false
var marker_position := Vector3.ZERO

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	_test_landing_solver()
	_test_rail_filtering.call_deferred()

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 180:
		carve_start_x = skier.global_position.x
		Input.action_press("steer_left", 1.0)
	elif frame == 330:
		Input.action_release("steer_left")
		if absf(skier.global_position.x - carve_start_x) < 0.5:
			failures.append("Carve input did not produce meaningful lateral travel")
		Input.action_press("jump", 1.0)
	elif frame == 350:
		Input.action_release("jump")
	elif frame > 350 and frame < 480 and skier.state == SkierController.State.AIR:
		air_seen = true
	elif frame == 480:
		if not air_seen:
			failures.append("Charged pop never entered Air state")
		marker_position = skier.global_position + Vector3.UP * 0.35
		var marker_transform := skier.global_transform
		marker_transform.origin = marker_position
		SessionManager.set_marker(marker_transform)
		skier.global_position += Vector3(9.0, 4.0, 0.0)
		SessionManager.request_respawn()
	elif frame == 500:
		if skier.global_position.distance_to(marker_position + Vector3.UP * 0.35) > 1.0:
			failures.append("Session marker respawn did not restore the saved position")
	elif frame == 620:
		speed_before_brake = skier.velocity.length()
		Input.action_press("brake", 1.0)
	elif frame == 740:
		Input.action_release("brake")
		if speed_before_brake > 4.0 and skier.velocity.length() >= speed_before_brake:
			failures.append("Brake did not reduce speed")
	elif frame == 760:
		_finish()

func _test_landing_solver() -> void:
	var profile := SkiPhysicsProfile.new()
	var clean := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0, -3, -10), Vector3.ZERO, profile)
	var failed := LandingSolver.evaluate(Vector3.DOWN, Vector3.FORWARD, Vector3.UP, Vector3(0, -22, -10), Vector3(8, 5, 2), profile)
	if int(clean.outcome) != LandingSolver.Outcome.CLEAN:
		failures.append("Nominal aligned landing was not classified clean")
	if int(failed.outcome) != LandingSolver.Outcome.BAIL:
		failures.append("Upside-down high-impact landing was not classified bail")

func _test_rail_filtering() -> void:
	var rail := resort.get_node("DownRail") as GrindRail3D
	var offset := rail.path_length * 0.5
	var position := rail.sample_world(offset) + Vector3.UP * 0.25
	var tangent := rail.tangent_at(offset)
	var valid := rail.capture_candidate(position, tangent * 10.0, 1.2, 3.0)
	var invalid := rail.capture_candidate(position + Vector3.RIGHT * 4.0, tangent * 10.0, 1.2, 3.0)
	if not bool(valid.get("valid", false)):
		failures.append("Plausible rail approach was rejected")
	if bool(invalid.get("valid", false)):
		failures.append("Far rail approach was incorrectly captured")

func _finish() -> void:
	Input.action_release("steer_left")
	Input.action_release("jump")
	Input.action_release("brake")
	print("ACCEPTANCE_TELEMETRY position=", skier.global_position, " speed_mps=", skier.velocity.length(), " state=", SkierController.State.keys()[skier.state])
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ACCEPTANCE_PASS: carve, pop, respawn, brake, landing, and rail entry checks passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ACCEPTANCE_FAIL: " + failure)
		get_tree().quit(1)
