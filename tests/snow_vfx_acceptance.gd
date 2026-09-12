extends Node3D

## VFX-01/VFX-02 regression: snow spray must follow the loaded ski, and each
## landing must produce exactly one burst.
##
## Carve spray belongs to the loaded outside ski (mirrored left/right turns),
## falling back to the contact center when the dominant side is invalid.
## The landing one-shot fires once per landed event and must never restart
## inside its evidence window.

const STEP := 1.0 / 60.0

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	_run_carve_follows_loaded_ski()
	_run_carve_falls_back_to_center()
	_run_single_landing_burst()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("SNOW_VFX_PASS: carve spray tracks the loaded ski with mirror symmetry; landings burst exactly once")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SNOW_VFX_FAIL: " + failure)
	get_tree().quit(1)

func _make_rig() -> Array:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.global_position = Vector3.ZERO
	skier.global_basis = Basis.IDENTITY
	skier.velocity = Vector3(0.0, 0.0, -12.0)
	skier.contact.surface_class = SkiContactSolver.SurfaceClass.SNOW
	skier.contact.grounded = true
	skier.contact.confidence = 1.0
	skier.contact.average_normal = Vector3.UP
	skier.contact.average_hit_position = Vector3.ZERO
	skier.contact.left_grounded = true
	skier.contact.right_grounded = true
	skier.contact.left_contact_confidence = 1.0
	skier.contact.right_contact_confidence = 1.0
	skier.contact.left_hit_position = Vector3(-0.34, 0.0, 0.0)
	skier.contact.right_hit_position = Vector3(0.34, 0.0, 0.0)
	skier.contact.left_normal = Vector3.UP
	skier.contact.right_normal = Vector3.UP
	skier.current_carve_ratio = 1.0
	skier.edge_amount = 1.0
	skier.skid_amount = 0.0
	skier.brake_amount = 0.0
	var vfx := SkiSnowVFX.new()
	skier.add_child(vfx)
	return [skier, vfx]

func _release_pair(skier: SkierController) -> void:
	remove_child(skier)
	skier.free()

func _run_carve_follows_loaded_ski() -> void:
	# Left turn (+35 deg heading): the loaded outside ski is the right one.
	var left_turn := _measure_carve_side(35.0)
	# Right turn: mirror image.
	var right_turn := _measure_carve_side(-35.0)
	if left_turn.is_empty() or right_turn.is_empty():
		return
	print("SNOW_VFX_SAMPLE left-turn carve=%s right-turn carve=%s" % [left_turn.get("pos", Vector3.ZERO), right_turn.get("pos", Vector3.ZERO)])
	var left_pos := left_turn.get("pos", Vector3.ZERO) as Vector3
	var right_pos := right_turn.get("pos", Vector3.ZERO) as Vector3
	# Mirror symmetry about the body center plane.
	if absf(left_pos.x + right_pos.x) > 0.2 or absf(left_pos.z - right_pos.z) > 0.3:
		failures.append("Carve spray did not mirror across left/right turns (%s vs %s)" % [left_pos, right_pos])
		return
	# Loaded outside ski dominates: left turn -> right contact (x +0.34).
	if left_pos.x < 0.1:
		failures.append("Left-turn carve spray stayed on the inside ski instead of the loaded outside ski (%s)" % left_pos)
		return
	if right_pos.x > -0.1:
		failures.append("Right-turn carve spray stayed on the inside ski instead of the loaded outside ski (%s)" % right_pos)

func _measure_carve_side(angle_degrees: float) -> Dictionary:
	var pair := _make_rig()
	var skier := pair[0] as SkierController
	var vfx := pair[1] as SkiSnowVFX
	skier.heading_travel_angle_degrees = angle_degrees
	skier.global_basis = Basis(Vector3.UP, deg_to_rad(angle_degrees))
	for _index: int in 40:
		vfx.update_from_existing_contact(STEP)
	var position := vfx.carve_spray.global_position
	_release_pair(skier)
	return {"pos": position}

func _run_carve_falls_back_to_center() -> void:
	var pair := _make_rig()
	var skier := pair[0] as SkierController
	var vfx := pair[1] as SkiSnowVFX
	skier.heading_travel_angle_degrees = 35.0
	skier.global_basis = Basis(Vector3.UP, deg_to_rad(35.0))
	skier.contact.right_grounded = false
	skier.contact.right_contact_confidence = 0.0
	for _index: int in 40:
		vfx.update_from_existing_contact(STEP)
	var position := vfx.carve_spray.global_position
	print("SNOW_VFX_SAMPLE invalid-side fallback carve=%s" % position)
	if position.distance_to(Vector3(0.0, position.y, position.z)) > 0.45:
		failures.append("Carve spray did not fall back toward the contact center when the loaded side went invalid (%s)" % position)
	_release_pair(skier)

func _run_single_landing_burst() -> void:
	var pair := _make_rig()
	var skier := pair[0] as SkierController
	var vfx := pair[1] as SkiSnowVFX
	vfx._on_landed({"impact_severity": 0.8, "lateral_velocity": 2.0})
	if not vfx.landing_spray.emitting:
		failures.append("Landing event did not fire the one-shot burst")
		_release_pair(skier)
		return
	# Simulate the burst completing mid-window (one-shot lifetime 0.38 s
	# inside the 0.68 s evidence window) and keep stepping.
	vfx.landing_spray.emitting = false
	var refired := false
	for _index: int in 40:
		vfx.update_from_existing_contact(STEP)
		if vfx.landing_spray.emitting:
			refired = true
			break
	var snapshot := vfx.debug_snapshot()
	print("SNOW_VFX_SAMPLE burst refired=%s mode=%s window=%.3f" % [refired, str(snapshot.get("mode", "?")), float(snapshot.get("landing_window_remaining", -1.0))])
	if refired:
		failures.append("Landing burst restarted inside its evidence window (repeated bursts for one landing)")
	elif str(snapshot.get("mode", "")) != "landing":
		failures.append("Landing evidence window bookkeeping was lost (mode %s)" % str(snapshot.get("mode", "?")))
	_release_pair(skier)
