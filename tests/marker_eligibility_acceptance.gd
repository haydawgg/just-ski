extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var ui: GameUI
var failures: Array[String] = []
var marker_saves: Array[Vector3] = []
var _press_pending := false
var _release_pending := false

func _physics_process(_delta: float) -> void:
	if _press_pending:
		Input.action_press(&"set_marker")
		_press_pending = false
		_release_pending = true
	elif _release_pending:
		Input.action_release(&"set_marker")
		_release_pending = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	skier = resort.get_node("Skier") as SkierController
	ui = resort.get_node("GameUI") as GameUI
	if skier == null or ui == null:
		failures.append("Resort did not expose skier and UI nodes")
		_finish()
		return
	SessionManager.marker_changed.connect(func(position: Vector3) -> void: marker_saves.append(position))
	_test_eligibility_matrix()
	if not failures.is_empty():
		_finish()
		return
	await _wait_for(func() -> bool: return skier.state == SkierController.State.GROUND and skier.contact.grounded and skier.contact.surface_class == SkiContactSolver.SurfaceClass.SNOW, 240)
	if skier.state != SkierController.State.GROUND or not skier.contact.grounded or skier.contact.surface_class != SkiContactSolver.SurfaceClass.SNOW:
		failures.append("Resort skier never settled onto grounded snow")
		_finish()
		return
	await _test_hotkey_on_snow()
	_test_menu_path_parity()
	if not failures.is_empty():
		_finish()
		return
	await _test_hotkey_airborne_blocked()
	_finish()

func _test_eligibility_matrix() -> void:
	var probe := SkierController.new()
	probe.set_physics_process(false)
	add_child(probe)
	var cases := [
		[SkierController.State.GROUND, SkiContactSolver.SurfaceClass.SNOW, true, true],
		[SkierController.State.GROUND, SkiContactSolver.SurfaceClass.FEATURE, true, false],
		[SkierController.State.GROUND, SkiContactSolver.SurfaceClass.METAL, true, false],
		[SkierController.State.GROUND, SkiContactSolver.SurfaceClass.UNKNOWN, true, false],
		[SkierController.State.GROUND, SkiContactSolver.SurfaceClass.SNOW, false, false],
		[SkierController.State.AIR, SkiContactSolver.SurfaceClass.SNOW, false, false],
		[SkierController.State.GRIND, SkiContactSolver.SurfaceClass.METAL, false, false],
		[SkierController.State.BAIL, SkiContactSolver.SurfaceClass.SNOW, true, false],
	]
	for case: Array in cases:
		probe.state = case[0]
		probe.contact.surface_class = case[1]
		probe.contact.grounded = case[2]
		if bool(case[3]) != probe.can_set_marker():
			failures.append(
				"Marker eligibility mismatch for state=%s surface=%s grounded=%s (expected %s)"
				% [SkierController.State.keys()[case[0]], SkiContactSolver.SurfaceClass.keys()[case[1]], str(case[2]), str(case[3])]
			)
	remove_child(probe)
	probe.queue_free()

func _test_hotkey_on_snow() -> void:
	var saves_before := marker_saves.size()
	if not skier.can_set_marker():
		failures.append("Settled snow state was not marker-eligible")
		return
	_press_pending = true
	if not await _wait_for(func() -> bool: return marker_saves.size() > saves_before, 30):
		failures.append("Marker hotkey did not save from grounded snow")
		return
	var marker := SessionManager.marker
	if marker.origin.distance_to(skier.global_position) > 2.5:
		failures.append("Hotkey marker was not saved at the skier position")
	var forward := -marker.basis.z
	if forward.z > -0.3:
		failures.append("Hotkey marker basis is not downhill-facing (forward=%s)" % str(forward))
	if absf(forward.y) > 0.9:
		failures.append("Hotkey marker basis is not on the snow plane (forward=%s)" % str(forward))

func _test_menu_path_parity() -> void:
	var saves_before := marker_saves.size()
	# Grounded BAIL must stay ineligible on the menu path even with snow contact.
	skier.set_physics_process(false)
	skier.state = SkierController.State.BAIL
	skier.contact.grounded = true
	skier.contact.surface_class = SkiContactSolver.SurfaceClass.SNOW
	ui._set_marker_from_menu()
	if marker_saves.size() != saves_before:
		failures.append("Menu marker path saved from a grounded BAIL state")
	# Eligible grounded snow on the menu path must match the hotkey decision.
	skier.state = SkierController.State.GROUND
	ui._set_marker_from_menu()
	if marker_saves.size() != saves_before + 1:
		failures.append("Menu marker path did not save from grounded snow")
	else:
		var forward := -SessionManager.marker.basis.z
		if forward.z > -0.3:
			failures.append("Menu marker basis is not downhill-facing (forward=%s)" % str(forward))
	skier.set_physics_process(true)

func _test_hotkey_airborne_blocked() -> void:
	var saves_before := marker_saves.size()
	skier.velocity = Vector3(0.0, 12.0, 0.0)
	if not await _wait_for(func() -> bool: return skier.state == SkierController.State.AIR, 60):
		failures.append("Pop launch did not enter AIR")
		return
	_press_pending = true
	for _frame: int in 30:
		await get_tree().physics_frame
		if marker_saves.size() != saves_before:
			failures.append("Marker hotkey saved while airborne (state=%s grounded=%s)" % [SkierController.State.keys()[skier.state], str(skier.contact.grounded)])
			return
		if skier.state != SkierController.State.AIR:
			break
	_press_pending = false
	_release_pending = false
	Input.action_release(&"set_marker")

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
		print("MARKER_ELIGIBILITY_PASS: centralized eligibility, fresh contact ordering, and sanitized bases passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("MARKER_ELIGIBILITY_FAIL: " + failure)
		get_tree().quit(1)
