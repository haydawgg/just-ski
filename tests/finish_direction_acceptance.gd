extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var ui: GameUI
var finish_trigger: Area3D
var failures: Array[String] = []
var finish_count := 0
var finish_z := -155.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	skier = resort.get_node("Skier") as SkierController
	ui = resort.get_node("GameUI") as GameUI
	finish_trigger = resort.get_node("FinishTrigger") as Area3D
	if skier == null or ui == null or finish_trigger == null:
		failures.append("Resort did not expose skier, UI, and finish trigger")
		_finish()
		return
	finish_z = finish_trigger.global_position.z
	skier.scoring.run_finished.connect(func(_snapshot: Dictionary) -> void: finish_count += 1)
	await _wait_for(func() -> bool: return skier.state == SkierController.State.GROUND and skier.contact.grounded, 240)
	# Armed downhill crossing completes the run.
	await _cross(Vector3(0.0, 0.0, -6.0), finish_z + 2.0, 0.0, 0.0, true, "armed downhill crossing", true)
	# Keep Riding resume, then the uphill exploit must be rejected.
	ui._results_continue()
	if get_tree().paused or bool(skier.scoring.snapshot().finished):
		failures.append("Keep Riding did not resume with a fresh scoring run before the crossing matrix")
		_finish()
		return
	await _cross(Vector3(0.0, 0.0, 6.0), finish_z - 2.0, 0.0, 0.0, false, "uphill crossing after Keep Riding", true)
	# Lateral drift-through is rejected.
	await _cross(Vector3(6.0, 0.0, 0.0), finish_z, 24.0, 0.0, false, "lateral crossing", true)
	# A below-threshold downhill drift is rejected.
	await _cross(Vector3(0.0, 0.0, -0.3), finish_z + 2.0, 0.0, 0.0, false, "slow entry", true)
	# An airborne downhill crossing still finishes.
	await _cross(Vector3(0.0, -2.0, -6.0), finish_z + 2.0, 0.0, 3.0, true, "airborne downhill crossing", true)
	# A bailed body tumbling downhill still finishes; results stay open.
	skier.state = SkierController.State.BAIL
	await _cross(Vector3(0.0, 0.0, -10.0), finish_z + 2.0, 0.0, 0.0, true, "bailed downhill crossing", false)
	# An already-finished run cannot finish again while the results are open.
	skier.velocity = Vector3.ZERO
	skier.global_position = Vector3(0.0, _surface_y(0.0, finish_z), finish_z + 40.0)
	await get_tree().physics_frame
	skier.velocity = Vector3(0.0, 0.0, -6.0)
	skier.global_position = Vector3(0.0, _surface_y(0.0, finish_z), finish_z)
	for _frame: int in 10:
		await get_tree().physics_frame
	if finish_count != 3:
		failures.append("Expected exactly three finish events, observed %d" % finish_count)
	if not ui.results_panel.visible or not get_tree().paused:
		failures.append("The blocked re-cross disturbed the results flow")
	ui._results_continue()
	_finish()

func _cross(velocity: Vector3, inside_z: float, inside_x: float, height_offset: float, should_finish: bool, label: String, dismiss_results: bool) -> void:
	skier.state = SkierController.State.GROUND
	skier.velocity = Vector3.ZERO
	skier.global_position = Vector3(inside_x, _surface_y(inside_x, inside_z) + 40.0, inside_z + 40.0)
	await get_tree().physics_frame
	skier.velocity = velocity
	skier.global_position = Vector3(inside_x, _surface_y(inside_x, inside_z) + height_offset, inside_z)
	for _frame: int in 12:
		await get_tree().physics_frame
		if should_finish and bool(skier.scoring.snapshot().finished):
			break
	var finished := bool(skier.scoring.snapshot().finished)
	if finished != should_finish:
		failures.append("%s finished=%s (expected %s)" % [label, str(finished), str(should_finish)])
	if should_finish:
		if not get_tree().paused or not ui.results_panel.visible:
			failures.append("%s did not open the paused results flow" % label)
		if dismiss_results:
			ui._results_continue()
			if get_tree().paused:
				failures.append("%s results dismiss did not resume" % label)
	else:
		if get_tree().paused or ui.results_panel.visible:
			failures.append("%s incorrectly opened the results flow" % label)
	skier.velocity = Vector3.ZERO

func _surface_y(x: float, z: float) -> float:
	return ParkLayout.surface_hover(x, z, ParkLayout.SPAWN_HOVER).y

func _wait_for(predicate: Callable, budget_frames: int) -> bool:
	var frames := budget_frames
	while frames > 0:
		if predicate.call():
			return true
		await get_tree().physics_frame
		frames -= 1
	return predicate.call()

func _finish() -> void:
	SessionManager.clear_marker()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("FINISH_DIRECTION_PASS: only armed downhill crossings complete the run")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FINISH_DIRECTION_FAIL: " + failure)
		get_tree().quit(1)
