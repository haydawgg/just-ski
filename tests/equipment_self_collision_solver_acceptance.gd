extends Node

const ProxyModule := preload("res://player/animation/equipment_collision_proxy.gd")
const ContextModule := preload("res://player/animation/equipment_collision_context.gd")
const SolverModule := preload("res://player/animation/equipment_self_collision_solver.gd")

var failures: Array[String] = []

func _ready() -> void:
	_test_translation_is_deterministic_and_bounded()
	_test_pivot_clears_a_body_capsule()
	_test_intentional_contact_tag_is_the_only_pair_exemption()
	_test_fixed_overlap_is_reported()
	_test_invalid_proxy_rejected()
	if failures.is_empty():
		print("EQUIPMENT_SELF_COLLISION_SOLVER_PASS: deterministic six-pass projection, bounded translation/pivot, exemptions, and diagnostics passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("EQUIPMENT_SELF_COLLISION_SOLVER_FAIL: " + failure)
	get_tree().quit(1)

func _test_translation_is_deterministic_and_bounded() -> void:
	var body := _proxy(&"body", ProxyModule.Kind.BODY, Vector3.ZERO, Vector3.ZERO, 0.20)
	var ski := _proxy(
		&"ski", ProxyModule.Kind.SKI,
		Vector3(0.10, 0.0, -0.5), Vector3(0.10, 0.0, 0.5), 0.075,
		&"ski_actuator", ProxyModule.Mobility.TRANSLATE)
	var forward: Array[EquipmentCollisionProxy] = [body, ski]
	var reverse: Array[EquipmentCollisionProxy] = [ski, body]
	var context := ContextModule.new() as EquipmentCollisionContext
	var solver := SolverModule.new() as EquipmentSelfCollisionSolver
	var first := solver.solve(forward, context)
	var second := solver.solve(reverse, context)
	var first_delta := first.translations.get(&"ski_actuator", Vector3.ZERO) as Vector3
	var second_delta := second.translations.get(&"ski_actuator", Vector3.ZERO) as Vector3
	if not first.unresolved_contacts.is_empty():
		failures.append("Movable ski did not clear a fixed body capsule")
	if not first_delta.is_equal_approx(second_delta):
		failures.append("Proxy input order changed the deterministic correction")
	if first_delta.length() <= 0.0 or first_delta.length() > ski.max_translation + 0.0001:
		failures.append("Translation correction was absent or exceeded its bound")
	if first.iterations != 6:
		failures.append("Solver no longer executes the configured six deterministic passes")

func _test_pivot_clears_a_body_capsule() -> void:
	var body := _proxy(
		&"body", ProxyModule.Kind.BODY,
		Vector3(0.12, -0.72, -0.05), Vector3(0.12, -0.72, 0.05), 0.12)
	var pole := _proxy(
		&"pole", ProxyModule.Kind.POLE,
		Vector3.ZERO, Vector3(0.0, -1.0, 0.0), 0.008,
		&"pole_actuator", ProxyModule.Mobility.PIVOT, Vector3.ZERO)
	var proxies: Array[EquipmentCollisionProxy] = [body, pole]
	var solver := SolverModule.new() as EquipmentSelfCollisionSolver
	var context := ContextModule.new() as EquipmentCollisionContext
	var result := solver.solve(proxies, context)
	if not result.directions.has(&"pole_actuator"):
		failures.append("Pole/body overlap did not produce a pivot direction")
	if not result.unresolved_contacts.is_empty():
		failures.append("Pivoting pole did not clear the fixed body capsule")

func _test_intentional_contact_tag_is_the_only_pair_exemption() -> void:
	var hand := _proxy(&"hand", ProxyModule.Kind.BODY, Vector3.ZERO, Vector3.ZERO, 0.08)
	var ski := _proxy(&"ski", ProxyModule.Kind.SKI, Vector3.ZERO, Vector3.ZERO, 0.08)
	hand.tags = [&"active_grab"]
	ski.tags = [&"active_grab"]
	var proxies: Array[EquipmentCollisionProxy] = [hand, ski]
	var solver := SolverModule.new() as EquipmentSelfCollisionSolver
	var context := ContextModule.new() as EquipmentCollisionContext
	var result := solver.solve(proxies, context)
	if result.pair_count != 0 or not result.unresolved_contacts.is_empty():
		failures.append("Shared intentional-contact tag was not excluded from candidate pairs")

func _test_fixed_overlap_is_reported() -> void:
	var body := _proxy(&"body", ProxyModule.Kind.BODY, Vector3.ZERO, Vector3.ZERO, 0.10)
	var boot := _proxy(&"boot", ProxyModule.Kind.BOOT, Vector3.ZERO, Vector3.ZERO, 0.10)
	var proxies: Array[EquipmentCollisionProxy] = [body, boot]
	var solver := SolverModule.new() as EquipmentSelfCollisionSolver
	var context := ContextModule.new() as EquipmentCollisionContext
	var result := solver.solve(proxies, context)
	if result.unresolved_contacts.size() != 1 or result.max_penetration <= 0.0:
		failures.append("Unresolvable fixed contact did not emit one penetration diagnostic")

func _test_invalid_proxy_rejected() -> void:
	var invalid := _proxy(&"", ProxyModule.Kind.SKI, Vector3.ZERO, Vector3.ZERO, 0.10)
	var proxies: Array[EquipmentCollisionProxy] = [invalid]
	var solver := SolverModule.new() as EquipmentSelfCollisionSolver
	var context := ContextModule.new() as EquipmentCollisionContext
	var result := solver.solve(proxies, context)
	if result.valid:
		failures.append("Invalid proxy was accepted")

func _proxy(
	id: StringName,
	kind: int,
	a: Vector3,
	b: Vector3,
	radius: float,
	actuator: StringName = &"",
	mobility: int = ProxyModule.Mobility.FIXED,
	pivot: Vector3 = Vector3.ZERO
) -> EquipmentCollisionProxy:
	var proxy := ProxyModule.new() as EquipmentCollisionProxy
	proxy.id = id
	proxy.kind = kind
	proxy.a = a
	proxy.b = b
	proxy.radius = radius
	proxy.actuator = actuator
	proxy.mobility = mobility
	proxy.pivot = pivot
	return proxy
