extends Node

const ResortScene := preload("res://world/resort.tscn")
const RATES := [30, 60, 120]

var failures: Array[String] = []
var resort: Node
var skier: SkierController
var ui: GameUI
var recovery: CourseRecovery
var finish_trigger: Area3D
var grind_rail: GrindRail3D
var respawn_count := 0
var finish_count := 0
var rail_outcomes: Array[StringName] = []
var rate := 60

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for rate_value: int in RATES:
		await _run_lifecycle(rate_value)
	Engine.physics_ticks_per_second = 60
	if failures.is_empty():
		print("SESSION_LIFECYCLE_MATRIX_PASS: integrated lifecycle held exactly-once semantics at 30/60/120 Hz")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SESSION_LIFECYCLE_MATRIX_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _run_lifecycle(rate_value: int) -> void:
	rate = rate_value
	Engine.physics_ticks_per_second = rate_value
	resort = ResortScene.instantiate()
	add_child(resort)
	skier = resort.get_node("Skier") as SkierController
	ui = resort.get_node("GameUI") as GameUI
	recovery = resort.get_node("CourseRecovery") as CourseRecovery
	finish_trigger = resort.get_node("FinishTrigger") as Area3D
	respawn_count = 0
	finish_count = 0
	rail_outcomes.clear()
	skier.respawn_applied.connect(func(_transform: Transform3D) -> void: respawn_count += 1)
	skier.scoring.run_finished.connect(func(_snapshot: Dictionary) -> void: finish_count += 1)
	skier.rail_finished.connect(func(_feature_id: StringName, outcome: StringName) -> void: rail_outcomes.append(outcome))
	if skier == null or ui == null or recovery == null or finish_trigger == null:
		failures.append("%d Hz: resort did not expose the lifecycle nodes" % rate)
		return
	var label := "%d Hz" % rate
	# Start: settle onto snow.
	if not await _wait_for(func() -> bool: return skier.state == SkierController.State.GROUND and skier.contact.grounded, _seconds(6.0)):
		failures.append("%s: skier never settled onto snow" % label)
		return
	# Trick: build an active scored run.
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("Lifecycle 360", 800, 0.9, LandingSolver.Outcome.CLEAN)
	if int(skier.scoring.total_score) != 800:
		failures.append("%s: lifecycle trick did not score 800" % label)
	# Crash: out-of-bounds recovery returns to the marker with preserved totals.
	SessionManager.set_marker(_snow_marker(Vector3(0.0, 0.0, 20.0)))
	skier.global_position = Vector3(96.0, skier.global_position.y, skier.global_position.z)
	if not await _wait_for(func() -> bool: return recovery.recovery_count == 1, _seconds(6.0)):
		failures.append("%s: recovery never completed the out-of-bounds crash" % label)
		return
	await _assert_stable(func() -> bool: return respawn_count == 1 and recovery.recovery_count == 1 and finish_count == 0, "%s: recovery window" % label)
	if int(skier.scoring.total_score) != 800 or int(skier.scoring.retry_count) != 0:
		failures.append("%s: recovery mutated persistent scoring (score %d retry %d)" % [label, skier.scoring.total_score, skier.scoring.retry_count])
	# Marker retry: explicit respawn applies exactly one retry cost.
	SessionManager.request_respawn()
	if not await _wait_for(func() -> bool: return respawn_count == 2, _seconds(3.0)):
		failures.append("%s: marker retry never respawned" % label)
		return
	await _assert_stable(func() -> bool: return respawn_count == 2, "%s: marker retry window" % label)
	if int(skier.scoring.retry_count) != 1:
		failures.append("%s: marker retry applied %d retry costs instead of 1" % [label, skier.scoring.retry_count])
	# Grind cancellation: a marker retry from GRIND cancels the rail attempt.
	await _settle_after_respawn()
	_prime_grind()
	SessionManager.request_respawn()
	if not await _wait_for(func() -> bool: return respawn_count == 3, _seconds(3.0)):
		failures.append("%s: grind cancellation never respawned" % label)
		return
	await _assert_stable(func() -> bool: return respawn_count == 3 and rail_outcomes.size() == 1, "%s: grind cancellation window" % label)
	if rail_outcomes.size() != 1 or rail_outcomes[0] != &"cancelled":
		failures.append("%s: grind cancellation produced %s instead of one cancellation" % [label, str(rail_outcomes)])
	# Finish: a downhill crossing completes the run once.
	await _settle_after_respawn()
	var finish_z := finish_trigger.global_position.z
	skier.velocity = Vector3(0.0, 0.0, -6.0)
	skier.global_position = Vector3(0.0, ParkLayout.surface_hover(0.0, finish_z, ParkLayout.SPAWN_HOVER).y, finish_z + 2.0)
	if not await _wait_for(func() -> bool: return finish_count == 1, _seconds(3.0)):
		failures.append("%s: downhill crossing never finished the run" % label)
		return
	await _assert_stable(func() -> bool: return finish_count == 1 and respawn_count == 3, "%s: finish window" % label)
	# Marker new run from the results screen starts a clean scoring run.
	ui._results_return_marker()
	if get_tree().paused:
		failures.append("%s: new-run results dismissal did not resume" % label)
	if not await _wait_for(func() -> bool: return respawn_count == 4, _seconds(3.0)):
		failures.append("%s: new-run marker never respawned" % label)
		return
	await _assert_stable(func() -> bool: return respawn_count == 4, "%s: new-run window" % label)
	var after_new_run := skier.scoring.snapshot()
	if int(after_new_run.total_score) != 0 or bool(after_new_run.finished) or int(after_new_run.retry_count) != 0:
		failures.append("%s: new-run marker did not start a clean run (score %d finished %s retry %d)" % [label, after_new_run.total_score, str(after_new_run.finished), after_new_run.retry_count])
	# Summit restart restarts the run from the top.
	await _settle_after_respawn()
	SessionManager.request_summit_restart()
	if not await _wait_for(func() -> bool: return respawn_count == 5, _seconds(3.0)):
		failures.append("%s: summit restart never respawned" % label)
		return
	await _assert_stable(func() -> bool: return respawn_count == 5 and finish_count == 1 and rail_outcomes.size() == 1, "%s: summit window" % label)
	var after_summit := skier.scoring.snapshot()
	if int(after_summit.total_score) != 0 or bool(after_summit.finished):
		failures.append("%s: summit restart did not produce a fresh run" % label)
	SessionManager.clear_marker()
	resort.queue_free()
	await get_tree().process_frame

func _settle_after_respawn() -> void:
	await _wait_for(func() -> bool: return skier.state == SkierController.State.GROUND and skier.contact.grounded, _seconds(6.0))

func _prime_grind() -> void:
	grind_rail = GrindRail3D.new()
	grind_rail.path = Curve3D.new()
	grind_rail.path.add_point(Vector3(0.0, 1.0, 10.0))
	grind_rail.path.add_point(Vector3(0.0, 1.2, -10.0))
	grind_rail.set_meta("feature_id", &"lifecycle_rail")
	resort.add_child(grind_rail)
	skier.active_rail = grind_rail
	skier.rail_offset = 4.0
	skier.rail_direction = 1.0
	skier.rail_speed = 10.0
	skier.rail_balance = 0.0
	skier.rail_balance_velocity = 0.0
	skier.state = SkierController.State.GRIND
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

func _snow_marker(at: Vector3) -> Transform3D:
	return Transform3D(ParkLayout.downhill_basis(), ParkLayout.surface_hover(at.x, at.z, ParkLayout.MARKER_HOVER))

func _seconds(value: float) -> int:
	return int(ceil(value * rate))

func _assert_stable(predicate: Callable, label: String) -> void:
	for _frame: int in _seconds(0.5):
		await get_tree().physics_frame
	if not predicate.call():
		failures.append("%s duplicate-event check failed" % label)

func _wait_for(predicate: Callable, budget_frames: int) -> bool:
	var frames := budget_frames
	while frames > 0:
		if predicate.call():
			return true
		await get_tree().physics_frame
		frames -= 1
	return predicate.call()
