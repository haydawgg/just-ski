extends Node3D

## CHAR-01/CHAR-03 regression: the physical contact footprint must not dictate
## the rendered ski stance.
##
## Drives real SkiContactSolver probe data (wide ±0.34 m physics sampling
## against real collision geometry) through SkierController animation-frame
## construction into the rig/IK, and measures ski/boot separation:
## flat snow reads hip-width/athletic (~0.36 m, not 0.68 m), cross-slope and
## uneven support stay bounded while preserving per-side snow height,
## single-side contact stays bounded, AIR handoff keeps ownership, landing
## preview stays bounded, and the rig/IK stage preserves the bounds.

const STEP := 1.0 / 60.0
const FLAT_SEPARATION_MIN := 0.31
const FLAT_SEPARATION_MAX := 0.41
const BOUNDED_SEPARATION_MIN := 0.18
const BOUNDED_SEPARATION_MAX := 0.53
const SINGLE_SIDE_LATERAL_MAX := 0.27

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	_run_flat_snow_preferred_stance()
	_run_cross_slope_bounded_stance()
	_run_uneven_terrain_bounded_widening()
	_run_single_side_confidence()
	_run_takeoff_handoff_ownership()
	_run_landing_preview_bounds()
	_run_rig_ik_preserves_bounds()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("STANCE_ACCEPTANCE_PASS: contact footprint decoupled from visual stance across flat, cross-slope, uneven, single-side, handoff, preview, and rig stages")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("STANCE_ACCEPTANCE_FAIL: " + failure)
	get_tree().quit(1)

func _make_box(size: Vector3, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = position
	body.rotation = rotation
	add_child(body)
	return body

func _make_skier(position: Vector3) -> SkierController:
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.state = SkierController.State.GROUND
	skier.global_position = position
	skier.global_basis = Basis.IDENTITY
	return skier

func _sample_contact(skier: SkierController) -> void:
	# Settle with repeated samples, like continuous gameplay: a single sample
	# after a teleport carries ~zero side confidence by design (continuity
	# term), so measure the converged state instead.
	for _index: int in 3:
		skier.contact.sample(
			skier,
			skier.profile.ground_probe_distance,
			skier.profile.ground_probe_reach,
			skier.profile.contact_probe_offsets(),
			skier.profile.ground_probe_origin_height
		)

func _release(nodes: Array) -> void:
	for node: Node in nodes:
		remove_child(node)
		node.free()

func _lateral_separation(skier: SkierController) -> float:
	var lateral := skier.global_basis.x.normalized()
	var left := skier.animation_frame.left_ski_target_world.origin as Vector3
	var right := skier.animation_frame.right_ski_target_world.origin as Vector3
	return (right - left).dot(lateral)

func _run_flat_snow_preferred_stance() -> void:
	var floor := _make_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	var skier := _make_skier(Vector3(0.0, 0.5, 0.0))
	_sample_contact(skier)
	if not skier.contact.left_grounded or not skier.contact.right_grounded:
		failures.append("Flat setup did not ground both probe sides")
		_release([skier, floor])
		return
	var probe_width := absf((skier.contact.right_hit_position - skier.contact.left_hit_position).dot(Vector3.RIGHT))
	skier._populate_animation_ski_targets()
	if not skier.animation_frame.left_ski_target_valid or not skier.animation_frame.right_ski_target_valid:
		failures.append("Flat snow produced no valid ski targets")
		_release([skier, floor])
		return
	var stance := _lateral_separation(skier)
	print("STANCE_SAMPLE flat probe=%.3f stance=%.3f" % [probe_width, stance])
	if stance < FLAT_SEPARATION_MIN or stance > FLAT_SEPARATION_MAX:
		failures.append("Flat snow stance %.3f m is not hip-width/athletic (need %.2f-%.2f, probes span %.2f)" % [stance, FLAT_SEPARATION_MIN, FLAT_SEPARATION_MAX, probe_width])
		_release([skier, floor])
		return
	var left_lateral := (skier.animation_frame.left_ski_target_world.origin - skier.global_position).dot(Vector3.RIGHT)
	var right_lateral := (skier.animation_frame.right_ski_target_world.origin - skier.global_position).dot(Vector3.RIGHT)
	if absf(left_lateral + right_lateral) > 0.05:
		failures.append("Flat snow stance is not centered on the body (%.3f / %.3f)" % [left_lateral, right_lateral])
	_release([skier, floor])

func _run_cross_slope_bounded_stance() -> void:
	var floor := _make_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0), Vector3(0.0, 0.0, deg_to_rad(12.0)))
	var skier := _make_skier(Vector3(0.0, 0.5, 0.0))
	_sample_contact(skier)
	if not skier.contact.left_grounded or not skier.contact.right_grounded:
		failures.append("Cross-slope setup did not ground both probe sides")
		_release([skier, floor])
		return
	skier._populate_animation_ski_targets()
	var stance := _lateral_separation(skier)
	var hit_height_diff := skier.contact.left_hit_position.y - skier.contact.right_hit_position.y
	var left_target := skier.animation_frame.left_ski_target_world.origin as Vector3
	var right_target := skier.animation_frame.right_ski_target_world.origin as Vector3
	var target_height_diff := left_target.y - right_target.y
	print("STANCE_SAMPLE cross stance=%.3f hit_dy=%.3f target_dy=%.3f" % [stance, hit_height_diff, target_height_diff])
	if stance < FLAT_SEPARATION_MIN or stance > FLAT_SEPARATION_MAX:
		failures.append("Cross-slope stance %.3f m escaped athletic bounds" % stance)
	elif absf(target_height_diff - hit_height_diff) > 0.04:
		failures.append("Cross-slope lost per-side snow height (hits %.3f, targets %.3f)" % [hit_height_diff, target_height_diff])
	_release([skier, floor])

func _run_uneven_terrain_bounded_widening() -> void:
	var floor := _make_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	var bump := _make_box(Vector3(0.6, 0.25, 2.5), Vector3(-0.34, 0.125, 0.0))
	var skier := _make_skier(Vector3(0.0, 0.5, 0.0))
	_sample_contact(skier)
	skier._populate_animation_ski_targets()
	if not skier.animation_frame.left_ski_target_valid or not skier.animation_frame.right_ski_target_valid:
		failures.append("Uneven terrain produced no valid ski targets")
		_release([skier, floor, bump])
		return
	var stance := _lateral_separation(skier)
	var left_target := skier.animation_frame.left_ski_target_world.origin as Vector3
	var right_target := skier.animation_frame.right_ski_target_world.origin as Vector3
	var target_height_diff := left_target.y - right_target.y
	print("STANCE_SAMPLE uneven stance=%.3f target_dy=%.3f" % [stance, target_height_diff])
	if stance < BOUNDED_SEPARATION_MIN or stance > BOUNDED_SEPARATION_MAX:
		failures.append("Uneven terrain stance %.3f m escaped presentation bounds" % stance)
	elif target_height_diff < 0.18 or target_height_diff > 0.32:
		failures.append("Uneven terrain did not preserve the bump height per side (dy %.3f)" % target_height_diff)
	_release([skier, floor, bump])

func _run_single_side_confidence() -> void:
	var floor := _make_box(Vector3(1.2, 1.0, 40.0), Vector3(0.9, -0.5, 0.0))
	var skier := _make_skier(Vector3(0.0, 0.5, 0.0))
	_sample_contact(skier)
	if skier.contact.left_grounded:
		failures.append("Single-side setup still grounded the left probes")
		_release([skier, floor])
		return
	skier._populate_animation_ski_targets()
	if skier.animation_frame.left_ski_target_valid:
		failures.append("Uncontacted left side still produced a ski target")
	elif not skier.animation_frame.right_ski_target_valid:
		failures.append("Contacted right side produced no ski target")
	else:
		var right_lateral := absf((skier.animation_frame.right_ski_target_world.origin - skier.global_position).dot(Vector3.RIGHT))
		print("STANCE_SAMPLE single-side right_lateral=%.3f" % right_lateral)
		if right_lateral > SINGLE_SIDE_LATERAL_MAX:
			failures.append("Single-side stance %.3f m mirrors the probe instead of the body" % right_lateral)
	_release([skier, floor])

func _run_takeoff_handoff_ownership() -> void:
	var floor := _make_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	var skier := _make_skier(Vector3(0.0, 0.5, 0.0))
	_sample_contact(skier)
	skier._populate_animation_ski_targets()
	if not skier.animation_frame.left_ski_target_valid:
		failures.append("Handoff setup produced no grounded targets")
		_release([skier, floor])
		return
	skier.state = SkierController.State.AIR
	skier._populate_animation_ski_targets()
	if skier.animation_frame.left_ski_target_valid or skier.animation_frame.right_ski_target_valid:
		failures.append("Takeoff handoff leaked contact ownership into AIR")
		_release([skier, floor])
		return
	skier.state = SkierController.State.GROUND
	skier._populate_animation_ski_targets()
	var stance := _lateral_separation(skier)
	if stance < FLAT_SEPARATION_MIN or stance > FLAT_SEPARATION_MAX:
		failures.append("Re-grounded stance %.3f m lost the decoupled width" % stance)
	_release([skier, floor])

func _run_landing_preview_bounds() -> void:
	var profile := load("res://resources/animation/default_animation_profile.tres") as SkierAnimationProfile
	if profile == null:
		failures.append("Could not load the animation profile resource")
		return
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.predicted_landing_valid = true
	frame.predicted_landing_time = 0.3
	frame.predicted_landing_normal = Vector3.UP
	frame.predicted_landing_point = Vector3(0.0, 0.0, -5.0)
	frame.velocity_heading = Vector3(0.0, 0.0, -1.0)
	frame.ski_forward = Vector3(0.0, 0.0, -1.0)
	var preview: Dictionary = LandingPoseLayer.air_preview_targets(
		frame, profile, profile.leg_ik_min_stance_width, Vector3(0.0, 1.2, 0.0), Basis.IDENTITY)
	if not bool(preview.get("valid", false)):
		failures.append("Landing preview produced no targets in its window")
		return
	var lateral := preview.get("lateral", Vector3.RIGHT) as Vector3
	var left := preview.get("left", Transform3D.IDENTITY) as Transform3D
	var right := preview.get("right", Transform3D.IDENTITY) as Transform3D
	var stance := (right.origin - left.origin).dot(lateral)
	var origin := preview.get("origin", Vector3.ZERO) as Vector3
	var centering := absf(((left.origin + right.origin) * 0.5 - origin).dot(lateral))
	print("STANCE_SAMPLE preview stance=%.3f centering=%.3f" % [stance, centering])
	if stance < 0.16 or stance > BOUNDED_SEPARATION_MAX:
		failures.append("Landing preview stance %.3f m escaped presentation bounds" % stance)
	elif centering > 0.03:
		failures.append("Landing preview stance is not centered on the body (%.3f)" % centering)

func _run_rig_ik_preserves_bounds() -> void:
	var floor := _make_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	var skier := _make_skier(Vector3(0.0, 0.5, 0.0))
	_sample_contact(skier)
	skier._populate_animation_ski_targets()
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.left_ski_target_world = skier.animation_frame.left_ski_target_world
	frame.right_ski_target_world = skier.animation_frame.right_ski_target_world
	frame.left_ski_target_valid = skier.animation_frame.left_ski_target_valid
	frame.right_ski_target_valid = skier.animation_frame.right_ski_target_valid
	var rig := SkierAnimationController.new()
	add_child(rig)
	for _index: int in 90:
		rig.apply_frame(frame, STEP)
	var snapshot := rig.debug_snapshot()
	var left_boot := snapshot.get("left_boot_target_world", Transform3D.IDENTITY) as Transform3D
	var right_boot := snapshot.get("right_boot_target_world", Transform3D.IDENTITY) as Transform3D
	var boot_stance := Vector2(right_boot.origin.x - left_boot.origin.x, right_boot.origin.z - left_boot.origin.z).length()
	print("STANCE_SAMPLE rig boot_stance=%.3f" % boot_stance)
	if boot_stance < 0.15 or boot_stance > 0.58:
		failures.append("Rig/IK boot stance %.3f m escaped presentation bounds" % boot_stance)
	_release([skier, floor, rig])
