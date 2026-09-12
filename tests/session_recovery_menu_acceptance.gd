extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var ui: GameUI
var recovery: CourseRecovery
var failures: Array[String] = []
var respawn_count := 0
var recovery_started_count := 0
var recovery_respawned_count := 0
var recovery_completed_count := 0
var recovery_cancelled_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	skier = resort.get_node("Skier") as SkierController
	ui = resort.get_node("GameUI") as GameUI
	recovery = resort.get_node("CourseRecovery") as CourseRecovery
	if skier == null or ui == null or recovery == null:
		failures.append("Resort did not expose skier, UI, and course recovery nodes")
		_finish()
		return
	skier.respawn_applied.connect(func(_transform: Transform3D) -> void: respawn_count += 1)
	recovery.recovery_started.connect(func(_reason: String) -> void: recovery_started_count += 1)
	recovery.recovery_respawned.connect(func(_reason: String, _transform: Transform3D) -> void: recovery_respawned_count += 1)
	recovery.recovery_completed.connect(func(_reason: String, _transform: Transform3D) -> void: recovery_completed_count += 1)
	recovery.recovery_cancelled.connect(func(_reason: String) -> void: recovery_cancelled_count += 1)
	await _test_menu_during_recovery_is_gated()
	await _test_foreign_respawn_cancels_recovery()
	_finish()

func _test_menu_during_recovery_is_gated() -> void:
	SessionManager.set_marker(_snow_marker_transform())
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("Menu Recovery Baseline", 1000, 0.9, LandingSolver.Outcome.CLEAN)
	var before := skier.scoring.snapshot()
	var serial_before := SessionManager.respawn_serial
	respawn_count = 0
	recovery_started_count = 0
	recovery_respawned_count = 0
	recovery_completed_count = 0
	recovery_cancelled_count = 0
	skier.global_position = Vector3(96.0, skier.global_position.y, skier.global_position.z)
	if not await _wait_for(func() -> bool: return recovery_started_count == 1, 120):
		failures.append("Out-of-bounds placement did not start course recovery")
		return
	# Pause inside the fade-out window and try every menu transition.
	ui._pause()
	if not get_tree().paused:
		failures.append("Pause menu did not pause the session")
	ui._respawn_from_menu()
	ui._restart_summit()
	ui._set_marker_from_menu()
	if SessionManager.respawn_serial != serial_before:
		failures.append("Menu respawn transitions fired during the recovery fade-out")
	if respawn_count != 0:
		failures.append("Menu transitions respawned the skier during the recovery fade-out")
	_check_menu_lock(true)
	ui._resume()
	if not await _wait_for(func() -> bool: return recovery_respawned_count == 1, 120):
		failures.append("Gated recovery did not issue its own respawn")
		return
	# Pause again inside the fade-in window, after the recovery respawn applied.
	ui._pause()
	ui._respawn_from_menu()
	ui._restart_summit()
	ui._set_marker_from_menu()
	if SessionManager.respawn_serial != serial_before + 1:
		failures.append("Menu respawn transitions fired during the recovery fade-in")
	if respawn_count != 1:
		failures.append("Menu transitions added a second respawn during the recovery fade-in")
	ui._resume()
	if not await _wait_for(func() -> bool: return recovery_completed_count == 1, 240):
		failures.append("Course recovery did not complete after menu gating")
		return
	for _frame: int in 3:
		await get_tree().physics_frame
	if recovery_cancelled_count != 0:
		failures.append("Gated menu transitions cancelled course recovery")
	if recovery_started_count != 1:
		failures.append("Gated menu transitions restarted course recovery")
	if respawn_count != 1:
		failures.append("One recovery produced %d respawns instead of exactly 1" % respawn_count)
	var after := skier.scoring.snapshot()
	if int(after.retry_count) != int(before.retry_count):
		failures.append("Recovery applied an unintended retry penalty")
	if int(after.total_score) != int(before.total_score) or str(after.best_trick_name) != str(before.best_trick_name) or int(after.landed_trick_count) != int(before.landed_trick_count):
		failures.append("Recovery changed persistent run scoring")
	if int(after.combo_count) != 0 or float(after.link_remaining) > 0.001:
		failures.append("Recovery did not clear transient combo/link state")
	if skier.recovery_frozen:
		failures.append("Recovery left the controller frozen after completion")
	if ui._recovery_active:
		failures.append("UI kept recovery active after completion")
	_check_menu_lock(false)

func _test_foreign_respawn_cancels_recovery() -> void:
	var serial_before := SessionManager.respawn_serial
	var started_before := recovery_started_count
	var cancelled_before := recovery_cancelled_count
	var completed_before := recovery_completed_count
	var respawns_before := respawn_count
	skier.global_position = Vector3(-96.0, skier.global_position.y, skier.global_position.z)
	if not await _wait_for(func() -> bool: return recovery_started_count == started_before + 1, 120):
		failures.append("Second out-of-bounds placement did not start course recovery")
		return
	# A foreign respawn owns the transition and must cancel the pending recovery respawn.
	SessionManager.request_respawn()
	if recovery_cancelled_count != cancelled_before + 1:
		failures.append("Foreign respawn did not cancel the active recovery")
	if recovery_started_count != started_before + 1:
		failures.append("Foreign respawn started an additional recovery")
	for _frame: int in 6:
		await get_tree().physics_frame
	if SessionManager.respawn_serial != serial_before + 1:
		failures.append("Foreign respawn produced extra respawn requests")
	if respawn_count != respawns_before + 1:
		failures.append("Foreign respawn path produced %d respawns instead of 1" % (respawn_count - respawns_before))
	if recovery_completed_count != completed_before:
		failures.append("Cancelled recovery still emitted completion")
	if recovery_respawned_count != 1:
		failures.append("Cancelled recovery emitted its own respawn afterwards")
	if skier.recovery_frozen:
		failures.append("Cancelled recovery left the controller frozen")
	if ui._recovery_active:
		failures.append("UI kept recovery active after cancellation")

func _check_menu_lock(locked: bool) -> void:
	for button_name in ["ReturnMarkerButton", "SetMarkerButton", "RestartButton"]:
		var button := ui.find_child(button_name, true, false) as Button
		if button == null:
			failures.append("Pause menu button %s missing" % button_name)
		elif button.disabled != locked:
			failures.append("%s disabled=%s while recovery_active=%s" % [button_name, str(button.disabled), str(locked)])

func _snow_marker_transform() -> Transform3D:
	return Transform3D(ParkLayout.downhill_basis(), ParkLayout.surface_hover(0.0, 20.0, ParkLayout.MARKER_HOVER))

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
		print("SESSION_RECOVERY_MENU_PASS: recovery owns its transition and menu transitions cannot re-enter it")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("SESSION_RECOVERY_MENU_FAIL: " + failure)
		get_tree().quit(1)
