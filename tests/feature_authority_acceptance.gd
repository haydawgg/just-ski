extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var failures: Array[String] = []
var events: Array[Dictionary] = []

func _ready() -> void:
	resort = $Resort
	skier = resort.get_node("Skier") as SkierController
	if skier == null:
		failures.append("Resort did not expose the skier")
		_finish()
		return
	skier.feature_used.connect(func(feature_id: StringName, feature_kind: StringName, use_kind: StringName) -> void:
		events.append({"feature_id": feature_id, "feature_kind": feature_kind, "use_kind": use_kind})
	)
	await _wait_for(func() -> bool: return skier.state == SkierController.State.GROUND and skier.contact.grounded, _seconds(6.0))
	if skier.state != SkierController.State.GROUND:
		failures.append("Resort skier never settled onto snow")
		_finish()
		return
	await _test_tabletop_deliberate_pop()
	await _test_roller_passive_release()
	await _test_butter_ride()
	await _test_proximity_negative()
	await _test_wallride_contact()
	_test_rail_capture()
	_finish()

func _test_tabletop_deliberate_pop() -> void:
	_reset_events()
	_launch(-12.0, _tabletop_launch_z(), 12.0)
	if not await _wait_for_event(&"small_table", &"ride", _seconds(5.0)):
		failures.append("Tabletop deck support never emitted a ride use")
		return
	skier._pop(skier.contact.average_normal, 1.0)
	if not await _wait_for_event(&"small_table", &"takeoff", _seconds(1.0)):
		failures.append("Deliberate tabletop pop did not emit a takeoff use")
	if _count(&"small_table", &"takeoff") != 1:
		failures.append("Tabletop emitted %d takeoff uses instead of 1" % _count(&"small_table", &"takeoff"))
	for event: Dictionary in events:
		if StringName(event.get("feature_id", &"")) == &"small_table" and StringName(event.get("use_kind", &"")) == &"ride":
			if StringName(event.get("feature_kind", &"")) != &"tabletop":
				failures.append("Tabletop ride use carried kind %s" % str(event.get("feature_kind", &"")))
			break

func _test_roller_passive_release() -> void:
	_reset_events()
	_launch(0.0, 135.0, 10.0)
	if not await _wait_for_event(&"summit_roller_a", &"ride", _seconds(5.0)):
		failures.append("Roller traversal never emitted a ride use")
		return
	if not await _wait_for(func() -> bool: return skier.state == SkierController.State.AIR, _seconds(2.5)):
		failures.append("Roller traversal never released into AIR")
		return
	await _wait_frames(8)
	if _count(&"summit_roller_a", &"takeoff") != 0:
		failures.append("Passive crest release credited a deliberate takeoff")

func _test_butter_ride() -> void:
	_reset_events()
	_launch(0.0, -30.0, 12.0)
	if not await _wait_for_event(&"mid_butter_pad", &"ride", _seconds(5.0)):
		failures.append("Butter pad traversal never emitted a ride use")

func _test_proximity_negative() -> void:
	_reset_events()
	_launch(2.0, _tabletop_launch_z(), 10.0)
	await _wait_frames(_seconds(4.0))
	if _count(&"small_table") != 0:
		failures.append("Passing 14 m from the tabletop credited a feature use")

func _test_wallride_contact() -> void:
	_reset_events()
	_launch(21.5, 48.0, 6.0)
	skier.velocity = Vector3(2.5, 0.0, -6.0)
	if not await _wait_for_event(&"mid_wallride", &"contact", _seconds(5.0)):
		failures.append("Sliding into the wallride never emitted a contact use")

func _test_rail_capture() -> void:
	_reset_events()
	var rail := resort.course_features.get("SummitFlatBox") as GrindRail3D
	if rail == null:
		failures.append("Resort did not expose the SummitFlatBox rail")
		return
	var offset := rail.path_length * 0.25
	skier.state = SkierController.State.AIR
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.global_transform = Transform3D(ParkLayout.downhill_basis(), rail.sample_world(offset))
	skier.velocity = rail.tangent_at(offset) * 12.0
	skier.active_rail = null
	skier._try_capture_rail()
	if _count(&"summit_flat_box", &"rail") != 1:
		failures.append("Rail capture did not emit exactly one rail use")
	elif skier.state != SkierController.State.GRIND or skier.active_rail != rail:
		failures.append("Rail capture did not enter the grind state")

func _tabletop_launch_z() -> float:
	var feature := resort.course_features.get("SmallTable") as Node3D
	if feature == null:
		failures.append("Resort did not expose the SmallTable feature")
		return 116.0
	var lip_z := float(feature.get_meta("lip_z", 110.0))
	var table_length := maxf(float(feature.get_meta("table_length", 8.0)), 2.0)
	return lip_z + table_length * 0.55

func _launch(x: float, z: float, speed: float) -> void:
	skier.reset_for_benchmark(
		Transform3D(ParkLayout.downhill_basis(), _surface_top(x, z) + Vector3.UP * 0.45),
		Vector3(0.0, 0.0, -speed)
	)

func _surface_top(x: float, z: float) -> Vector3:
	var fallback := ParkLayout.surface_hover(x, z, ParkLayout.SPAWN_HOVER)
	if resort == null:
		return fallback
	var space := resort.get_world_3d().direct_space_state
	var from := Vector3(x, fallback.y + 30.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 80.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return hit.position as Vector3

func _reset_events() -> void:
	events.clear()

func _count(feature_id: StringName, use_kind: StringName = &"") -> int:
	var total := 0
	for event: Dictionary in events:
		if StringName(event.get("feature_id", &"")) != feature_id:
			continue
		if use_kind != &"" and StringName(event.get("use_kind", &"")) != use_kind:
			continue
		total += 1
	return total

func _wait_for_event(feature_id: StringName, use_kind: StringName, budget_frames: int) -> bool:
	var frames := budget_frames
	while frames > 0:
		if _count(feature_id, use_kind) > 0:
			return true
		await get_tree().physics_frame
		frames -= 1
	return _count(feature_id, use_kind) > 0

func _wait_frames(budget_frames: int) -> void:
	for _frame: int in budget_frames:
		await get_tree().physics_frame

func _wait_for(predicate: Callable, budget_frames: int) -> bool:
	var frames := budget_frames
	while frames > 0:
		if predicate.call():
			return true
		await get_tree().physics_frame
		frames -= 1
	return predicate.call()

func _seconds(value: float) -> int:
	return int(ceil(value * float(Engine.physics_ticks_per_second)))

func _finish() -> void:
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("FEATURE_AUTHORITY_PASS: ride, deliberate takeoff, rail capture, wallride contact, and proximity rejection verified")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("FEATURE_AUTHORITY_FAIL: " + failure)
	get_tree().quit(1)
