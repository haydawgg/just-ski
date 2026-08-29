extends Node

var failures: Array[String] = []

func _ready() -> void:
	_test_guarded_crash_entry_and_respawn_cleanup()
	_test_repeated_crash_respawn_cycles()
	await _test_failed_landing_emits_crash_only()
	await _test_feature_collision_thresholds()
	await _test_bounded_rest_and_recovery()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CRASH_RECOVERY_PASS: guarded entry, momentum, scoring, telemetry, rest, recovery, and respawn cleanup passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CRASH_RECOVERY_FAIL: " + failure)
	get_tree().quit(1)

func _test_guarded_crash_entry_and_respawn_cleanup() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(7.0, -2.0, -14.0))
	skier.angular_velocity = Vector3(0.8, 2.2, -0.5)
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("Baseline 360", 400, 0.9)
	var score_before := skier.scoring.snapshot()
	var crash_signals := [0]
	skier.crashed.connect(func() -> void: crash_signals[0] += 1)

	var context := CrashContext.new()
	context.begin(
		CrashContext.Reason.LANDING_ANGULAR,
		CrashContext.Source.LANDING,
		SkierController.State.AIR,
		Vector3(7.0, -2.0, -14.0),
		Vector3(7.0, -2.0, -14.0),
		Vector3.UP,
		2.0,
		skier.angular_velocity.length(),
		0.92
	)
	var first_entry := skier.enter_crash(context)
	var second_entry := skier.enter_crash(context)
	var crash_telemetry := skier.telemetry().crash as Dictionary
	var score_after := skier.scoring.snapshot()
	if not first_entry or second_entry:
		failures.append("Crash entry was not guarded against duplicate processing")
	if crash_signals[0] != 1 or int(score_after.bail_count) != 1:
		failures.append("Crash signal or scoring bail count was not emitted exactly once")
	if skier.velocity.distance_to(Vector3(7.0, -2.0, -14.0)) > 0.001:
		failures.append("Crash entry discarded incoming linear momentum")
	if skier.angular_velocity.length() < 1.0:
		failures.append("Crash entry zeroed angular momentum")
	if int(score_after.total_score) != int(score_before.total_score) or str(score_after.best_trick_name) != str(score_before.best_trick_name):
		failures.append("Crash entry did not preserve total score and best trick")
	if str(crash_telemetry.reason) != "LANDING_ANGULAR" or str(crash_telemetry.stage) != "RELEASE":
		failures.append("Crash telemetry did not expose authoritative reason and stage")

	skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	var respawn_telemetry := skier.telemetry()
	if bool((respawn_telemetry.crash as Dictionary).active):
		failures.append("Respawn retained active crash context")
	if skier.state != SkierController.State.AIR or skier.velocity.length() > 0.001 or skier.angular_velocity.length() > 0.001:
		failures.append("Respawn did not restore a clean airborne reset state")
	remove_child(skier)
	skier.queue_free()

func _test_repeated_crash_respawn_cycles() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3.ZERO)
	var crash_signals := [0]
	skier.crashed.connect(func() -> void: crash_signals[0] += 1)
	for cycle: int in 20:
		var incoming_velocity := Vector3(4.0 + float(cycle) * 0.1, -1.5, -9.0)
		skier.velocity = incoming_velocity
		skier.angular_velocity = Vector3(0.2, 0.7, -0.1)
		var context := CrashContext.new()
		context.begin(
			CrashContext.Reason.FEATURE_IMPACT,
			CrashContext.Source.OBSTACLE,
			SkierController.State.AIR,
			incoming_velocity,
			incoming_velocity.slide(Vector3.RIGHT),
			Vector3.LEFT,
			incoming_velocity.x,
			0.8,
			0.0
		)
		if not skier.enter_crash(context):
			failures.append("Repeated cycle %d could not enter crash" % cycle)
			break
		if not bool((skier.telemetry().crash as Dictionary).active):
			failures.append("Repeated cycle %d did not publish active crash telemetry" % cycle)
			break
		skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
		if skier.state != SkierController.State.AIR or bool((skier.telemetry().crash as Dictionary).active):
			failures.append("Repeated cycle %d retained stale crash state after respawn" % cycle)
			break
	var score := skier.scoring.snapshot()
	if crash_signals[0] != 20 or int(score.bail_count) != 20:
		failures.append("Repeated crash/respawn cycles lost or duplicated crash accounting")
	if int(skier.telemetry().respawn_count) != 20:
		failures.append("Repeated crash/respawn cycles did not retain authoritative respawn telemetry")
	remove_child(skier)
	skier.queue_free()

func _test_bounded_rest_and_recovery() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 0.5, 30.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.25, 0.0)
	add_child(floor_body)

	var skier := SkierController.new()
	add_child(skier)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)), Vector3(0.4, -1.0, -0.7))
	skier.angular_velocity = Vector3(0.15, 0.2, 0.1)
	var context := CrashContext.new()
	context.begin(
		CrashContext.Reason.LANDING_UPRIGHT,
		CrashContext.Source.LANDING,
		SkierController.State.AIR,
		skier.velocity,
		skier.velocity,
		Vector3.UP,
		1.0,
		skier.angular_velocity.length(),
		1.0
	)
	skier.enter_crash(context)
	var frames := 0
	while skier.state == SkierController.State.BAIL and frames < 420:
		await get_tree().physics_frame
		frames += 1
	if skier.state != SkierController.State.GROUND:
		failures.append("Low-speed crash did not reach bounded rest and recover")
	if frames < 20:
		failures.append("Crash recovered before a readable minimum crash duration")
	if bool((skier.telemetry().crash as Dictionary).active):
		failures.append("In-place recovery retained active crash state")
	remove_child(skier)
	skier.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _test_failed_landing_emits_crash_only() -> void:
	var floor_body := _make_box_body("LandingFloor", 1, Vector3(30.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0))
	var skier := SkierController.new()
	add_child(skier)
	var sideways_basis := Basis(Vector3.FORWARD, PI * 0.5)
	skier.reset_for_benchmark(Transform3D(sideways_basis, Vector3(0.0, 1.1, 0.0)), Vector3(0.0, -5.0, -6.0))
	skier.air_deliberate = true
	skier.air_time = 0.2
	skier.landing_feedback_armed = true
	var landed_signals := [0]
	var crash_signals := [0]
	skier.landed.connect(func(_result: Dictionary) -> void: landed_signals[0] += 1)
	skier.crashed.connect(func() -> void: crash_signals[0] += 1)
	var frames := 0
	while skier.state != SkierController.State.BAIL and frames < 120:
		await get_tree().physics_frame
		frames += 1
	if skier.state != SkierController.State.BAIL:
		failures.append("Unrecoverable real landing did not enter crash state")
	elif str((skier.telemetry().crash as Dictionary).reason) != "LANDING_UPRIGHT":
		failures.append("Unrecoverable real landing reported the wrong crash reason")
	if landed_signals[0] != 0 or crash_signals[0] != 1:
		failures.append("Failed landing emitted successful landing feedback or duplicate crash feedback")
	remove_child(skier)
	skier.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _test_feature_collision_thresholds() -> void:
	var wall := _make_box_body("FeatureWall", 4, Vector3(0.5, 8.0, 12.0), Vector3(3.0, 2.0, 0.0))
	var fast_skier := SkierController.new()
	add_child(fast_skier)
	fast_skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)), Vector3(14.0, 0.0, 0.0))
	var frames := 0
	while fast_skier.state != SkierController.State.BAIL and frames < 90:
		await get_tree().physics_frame
		frames += 1
	var fast_crash := fast_skier.telemetry().crash as Dictionary
	if fast_skier.state != SkierController.State.BAIL:
		failures.append("High-speed feature impact did not trigger crash (position=%s velocity=%s collisions=%s diagnostics=%s)" % [fast_skier.global_position, fast_skier.velocity, fast_skier.last_collision_colliders, fast_skier.last_collision_diagnostics])
	elif str(fast_crash.reason) != "FEATURE_IMPACT" or str(fast_crash.source) != "OBSTACLE":
		failures.append("Feature impact did not preserve obstacle crash context")
	elif float(fast_crash.impact_speed) < fast_skier.profile.feature_collision_min_normal_speed:
		failures.append("Feature crash telemetry lost incoming normal impact speed")
	remove_child(fast_skier)
	fast_skier.queue_free()

	var slow_skier := SkierController.new()
	add_child(slow_skier)
	slow_skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)), Vector3(3.0, 0.0, 0.0))
	for _index: int in 120:
		await get_tree().physics_frame
		if slow_skier.state == SkierController.State.BAIL:
			break
	if slow_skier.state == SkierController.State.BAIL:
		failures.append("Low-speed feature contact incorrectly triggered crash")
	remove_child(slow_skier)
	slow_skier.queue_free()
	remove_child(wall)
	wall.queue_free()

func _make_box_body(body_name: String, layer: int, size: Vector3, body_position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = body_position
	add_child(body)
	return body
