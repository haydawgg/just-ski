extends Node

const CollisionLayers := preload("res://resources/physics/collision_layers.gd")

var failures: Array[String] = []

func _ready() -> void:
	_test_crash_presentation_clock_and_notice()
	_test_airborne_crash_rotation_continuity()
	_test_guarded_crash_entry_and_respawn_cleanup()
	_test_repeated_crash_respawn_cycles()
	_test_reseat_landing_outcomes_and_trick_cleanup()
	_test_finished_respawn_starts_new_run()
	_test_ground_fallback_preserves_pop()
	_test_ground_angle_contract()
	_test_landing_prediction_cache()
	_test_bail_rest_damping()
	_test_fall_rotation_softening_preserves_linear_motion()
	_test_crash_entry_clears_locomotion()
	_test_grounded_crash_tumbles_gradually()
	_test_bail_collider_stays_surface_aligned()
	_test_bail_probe_footprint_stays_on_surface()
	_test_surface_roll_axis_on_flat_and_slope()
	_test_surface_roll_reverses_with_travel()
	_test_surface_roll_grows_with_speed_and_respects_cap()
	_test_zero_speed_does_not_generate_roll()
	_test_travel_direction_sprawl()
	_test_degenerate_roll_inputs_remain_finite()
	_test_grounded_tumble_respects_rotation_bounds()
	_test_airborne_bail_continuity_unchanged()
	_test_ground_alignment_weakens_with_speed()
	_test_rest_detection_and_recovery_timing()
	_test_crash_severity_duration_bands()
	_test_hybrid_ragdoll_contract()
	_test_ragdoll_telemetry_contract()
	await _test_ragdoll_ground_and_joint_stability()
	_test_rest_waits_for_snow_alignment()
	_test_crash_settling_shows_low_speed_motion()
	_test_recovery_is_rate_limited_and_coordinated()
	await _test_world_origin_seating()
	await _test_landing_requires_close_support()
	_test_pop_preserves_impulse()
	await _test_failed_landing_emits_crash_only()
	await _test_feature_collision_thresholds()
	await _test_airborne_bail_timeout_respawns()
	await _test_airborne_contact_normal_refresh()
	await _test_grind_feature_collision_enters_bail()
	await _test_bounded_rest_and_recovery()
	await _test_recovery_freeze_ignores_session_input()
	await _test_marker_retry_scoring_policy()
	await _test_course_recovery_lifecycle_and_scoring()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CRASH_RECOVERY_PASS: locomotion state, momentum, scoring, telemetry, rest, recovery, and respawn cleanup passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CRASH_RECOVERY_FAIL: " + failure)
	get_tree().quit(1)

func _test_world_origin_seating() -> void:
	var floor_body := _make_box_body("OriginFloor", 1, Vector3(30.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0))
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	await get_tree().physics_frame
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.0)), Vector3(0.0, -0.5, 0.0))
	skier.air_time = 0.2
	skier.air_deliberate = true
	skier._physics_process(1.0 / 60.0)
	if skier.contact.hit_points.is_empty() or skier.contact.average_hit_position.length() > 0.001:
		failures.append("Origin seating fixture did not sample real terrain at the world origin")
	if skier.state != SkierController.State.GROUND or absf(skier.global_position.y - skier.profile.ground_attach_height) > 0.002:
		failures.append("Valid world-origin contact was treated as missing and left the landed skier hovering")
	remove_child(skier)
	skier.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _test_landing_requires_close_support() -> void:
	var floor_body := _make_box_body("TouchdownFloor", 1, Vector3(30.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0))
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	await get_tree().physics_frame
	for deliberate: bool in [false, true]:
		skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.72, 0.0)), Vector3(0.0, -0.5, 0.0))
		skier.air_time = 0.2
		skier.air_deliberate = deliberate
		skier._physics_process(1.0 / 60.0)
		if skier.state != SkierController.State.AIR:
			failures.append("Landing accepted distant snow support with %.3f m clearance (deliberate=%s)" % [0.72 - skier.profile.ground_attach_height, deliberate])
		var frames := 0
		while skier.state == SkierController.State.AIR and frames < 120:
			await get_tree().physics_frame
			skier._physics_process(1.0 / 60.0)
			frames += 1
		var seat_tolerance := 0.002 if deliberate else 0.05
		if skier.state != SkierController.State.GROUND or absf(skier.global_position.y - skier.profile.ground_attach_height) > seat_tolerance:
			failures.append("Touchdown did not enter grounded locomotion at the support surface (deliberate=%s height=%.3f)" % [deliberate, skier.global_position.y])
	for elapsed_air_time: float in [0.0, 0.2]:
		skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.0)), Vector3(0.0, -16.0, 0.0))
		skier.air_time = elapsed_air_time
		skier.air_deliberate = true
		for _index: int in 3:
			skier._physics_process(1.0 / 60.0)
			if skier.get_slide_collision_count() > 0 and skier.state == SkierController.State.AIR:
				failures.append("Physical snow collision left airborne/trick processing active for another tick")
			if skier.state != SkierController.State.AIR:
				break
		var impact := skier.crash_context.impact_speed if skier.state == SkierController.State.BAIL else float(skier.landing_context.get("impact", 0.0))
		if impact < 15.0:
			failures.append("Touchdown discarded incoming collision speed (impact=%.3f)" % impact)
	remove_child(skier)
	skier.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _test_pop_preserves_impulse() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	var normal := Vector3(0.0, 1.0, 0.3).normalized()
	var tangent := Vector3.RIGHT * 8.0
	for approach_speed: float in [-1.4, 0.0, 2.0]:
		skier.state = SkierController.State.GROUND
		skier.velocity = tangent + normal * approach_speed
		skier._pop(normal, 1.0)
		if absf(skier.velocity.dot(normal) - (skier.profile.pop_impulse + maxf(0.0, approach_speed))) > 0.001:
			failures.append("Suspension velocity consumed the pop impulse or upward momentum was lost")
		if skier.velocity.slide(normal).distance_to(tangent) > 0.001:
			failures.append("Pop changed tangential skiing momentum")
	remove_child(skier)
	skier.queue_free()

func _test_crash_presentation_clock_and_notice() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3.ZERO)
	var ui := GameUI.new()
	add_child(ui)
	ui.set_process(false)
	ui.bind_player(skier)
	skier._bail()
	ui._process(3.0)
	if ui.notice_label.modulate.a < 0.99 or "BAIL" not in ui.notice_label.text:
		failures.append("Bail notice expired while the player was still in BAIL")
	ui._show_notice("SESSION MARKER SAVED")
	if "BAIL" not in ui.notice_label.text:
		failures.append("An unrelated notice replaced the active bail status")
	skier.crash_context.elapsed = 3.0
	skier.contact.grounded = true
	for stage: int in [CrashContext.Stage.IMPACT, CrashContext.Stage.FALL, CrashContext.Stage.REST, CrashContext.Stage.RECOVERY]:
		skier.crash_context.set_stage(stage)
		skier._update_animation(1.0 / 60.0)
		if skier.animation_controller._crash_stage_progress > 0.001:
			failures.append("Crash stage %s presentation started at %.2f instead of zero on the handoff" % [CrashContext.Stage.keys()[stage], skier.animation_controller._crash_stage_progress])
	ui._process(3.0)
	if "getting up" not in ui.notice_label.text or ui.notice_label.modulate.a < 0.99:
		failures.append("Recovery did not retain a visible get-up status")
	skier._recover_from_bail()
	ui._process(1.0 / 60.0)
	if ui.notice_label.modulate.a > 0.01 and "BAIL" in ui.notice_label.text:
		failures.append("Bail notice survived the completed recovery")
	ui._show_notice("SETTINGS SAVED")
	if ui.notice_label.text != "SETTINGS SAVED" or ui.notice_label.modulate.a < 0.99:
		failures.append("Recovery broke ordinary HUD notices")
	ui._process(3.0)
	if ui.notice_label.modulate.a > 0.01:
		failures.append("Ordinary HUD notices no longer expire")
	skier._bail()
	ui.bind_player(skier)
	if "BAIL" not in ui.notice_label.text or ui.notice_label.modulate.a < 0.99:
		failures.append("Binding the HUD during a crash missed its active status")
	skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	ui._process(1.0 / 60.0)
	if "BAIL" in ui.notice_label.text:
		failures.append("Respawn retained stale bail status")
	remove_child(ui)
	ui.queue_free()
	remove_child(skier)
	skier.queue_free()

func _test_airborne_crash_rotation_continuity() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var initial_basis := Basis(axis, deg_to_rad(150.0))
		skier.reset_for_benchmark(Transform3D(initial_basis, Vector3(0.0, 10.0, 0.0)), Vector3.DOWN)
		skier.angular_velocity = axis * 1.0
		skier._bail()
		skier.contact.grounded = false
		skier._update_bail(1.0 / 60.0)
		var turn := initial_basis.get_rotation_quaternion().angle_to(skier.global_basis.get_rotation_quaternion())
		if turn > 0.04:
			failures.append("Airborne crash snapped %.1f degrees in one tick instead of following angular momentum" % rad_to_deg(turn))
		if skier.angular_velocity.dot(axis) < 0.9:
			failures.append("Airborne crash discarded tumble momentum before snow contact")
	remove_child(skier)
	skier.queue_free()

func _test_guarded_crash_entry_and_respawn_cleanup() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(7.0, -2.0, -14.0))
	skier.angular_velocity = Vector3(0.8, 2.2, -0.5)
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("Baseline 360", 400, 0.9, LandingSolver.Outcome.CLEAN)
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
	context.attach_collision_diagnostic({"collider": "TestWall", "asset_id": "test_wall", "collider_layer": 4, "normal": Vector3.LEFT, "position": Vector3.ZERO})
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

	var emitted_score_snapshot: Dictionary = {}
	skier.scoring.score_changed.connect(func(snapshot: Dictionary) -> void: emitted_score_snapshot = snapshot)
	skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	var respawn_telemetry := skier.telemetry()
	if bool((respawn_telemetry.crash as Dictionary).active):
		failures.append("Respawn retained active crash context")
	var cleared_crash := respawn_telemetry.crash as Dictionary
	if not str(cleared_crash.get("collision_collider", "")).is_empty() or int(cleared_crash.get("collision_layer", 0)) != 0:
		failures.append("Respawn retained stale crash collision diagnostics")
	if float(emitted_score_snapshot.get("link_remaining", 0.0)) > 0.001 or not str(emitted_score_snapshot.get("last_feature_kind", "")).is_empty():
		failures.append("Respawn score_changed signal exposed stale line-link state")
	if skier.state != SkierController.State.AIR or skier.velocity.length() > 0.001 or skier.angular_velocity.length() > 0.001:
		failures.append("Respawn did not restore a clean airborne reset state")
	var reset_score := skier.scoring.snapshot()
	if int(reset_score.total_score) != int(score_before.total_score) or int(reset_score.combo_count) != 0 or float(reset_score.link_remaining) > 0.001 or str(reset_score.last_combo_break_reason) != "respawn":
		failures.append("Respawn did not preserve total score while clearing combo/link state")
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

func _test_reseat_landing_outcomes_and_trick_cleanup() -> void:
	var failed_landed_signals := [0]
	var failed_skier := SkierController.new()
	add_child(failed_skier)
	failed_skier.set_physics_process(false)
	failed_skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, -5.0, -6.0))
	failed_skier.contact.grounded = true
	failed_skier.contact.average_normal = Vector3.UP
	failed_skier.global_basis = Basis(Vector3.RIGHT, PI)
	failed_skier.air_time = 0.25
	failed_skier.air_deliberate = false
	failed_skier.landing_feedback_armed = true
	failed_skier.trick.begin_air(false, TrickCommand.Kind.BACKFLIP, true, Vector3.RIGHT)
	failed_skier.active_trick_kind = TrickCommand.Kind.BACKFLIP
	failed_skier.landed.connect(func(_result: Dictionary) -> void: failed_landed_signals[0] += 1)
	failed_skier._reseat_on_snow()
	if failed_skier.state != SkierController.State.BAIL:
		failures.append("Reseat BAIL outcome incorrectly wrote GROUND")
	if not bool((failed_skier.telemetry().crash as Dictionary).active):
		failures.append("Reseat BAIL outcome did not create active crash context")
	if failed_landed_signals[0] != 0:
		failures.append("Reseat BAIL outcome emitted successful landing feedback")
	if failed_skier.trick.active or failed_skier.trick.had_trick_intent:
		failures.append("Reseat BAIL outcome retained active trick state")
	remove_child(failed_skier)
	failed_skier.queue_free()

	var clean_skier := SkierController.new()
	add_child(clean_skier)
	clean_skier.set_physics_process(false)
	clean_skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, -0.5, -6.0))
	clean_skier.contact.grounded = true
	clean_skier.contact.average_normal = Vector3.UP
	clean_skier.air_time = 0.25
	clean_skier.air_deliberate = false
	clean_skier.trick.begin_air(false, TrickCommand.Kind.BACKFLIP, true, Vector3.RIGHT)
	clean_skier.active_trick_kind = TrickCommand.Kind.BACKFLIP
	clean_skier._reseat_on_snow()
	if clean_skier.state != SkierController.State.GROUND:
		failures.append("Recoverable reseat did not reach GROUND")
	if clean_skier.trick.active or clean_skier.trick.had_trick_intent:
		failures.append("Successful reseat leaked airborne trick state")
	if int(clean_skier.scoring.snapshot().total_score) != 0:
		failures.append("Successful reseat incorrectly awarded trick score")
	remove_child(clean_skier)
	clean_skier.queue_free()

func _test_finished_respawn_starts_new_run() -> void:
	SessionManager.clear_marker()
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3.ZERO)
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("Finished Run Test", 300, 1.0, LandingSolver.Outcome.CLEAN)
	skier.scoring.finish_run()
	if not skier.scoring.finished:
		failures.append("Finished-run setup did not enter finished state")
	skier.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)))
	var reset_snapshot := skier.scoring.snapshot()
	if bool(reset_snapshot.finished) or int(reset_snapshot.total_score) != 0:
		failures.append("Respawn after finish did not reset the scoring run")
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("New Run Test", 100, 1.0, LandingSolver.Outcome.CLEAN)
	if bool(skier.scoring.finished) or int(skier.scoring.snapshot().total_score) <= 0:
		failures.append("Respawn after finish left the new run unscorable")
	remove_child(skier)
	skier.queue_free()

func _test_ground_fallback_preserves_pop() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_basis = Basis(Vector3.RIGHT, PI * 0.5)
	skier.trick_command.pop_strength = 1.0
	skier.trick_command.kind = TrickCommand.Kind.POP
	skier._update_ground(1.0 / 60.0)
	if skier.state != SkierController.State.AIR or skier.velocity.y <= 0.0:
		failures.append("Degenerate grounded heading skipped the pop instead of using a tangent fallback")
	remove_child(skier)
	skier.queue_free()

func _test_ground_angle_contract() -> void:
	var contact := SkiContactSolver.new()
	var accepted_angle := deg_to_rad(61.9)
	var accepted_normal := Vector3(sin(accepted_angle), cos(accepted_angle), 0.0)
	contact.merge_capsule_floor(true, accepted_normal, 62.0)
	if not contact.grounded:
		failures.append("Contact solver rejected a slope inside the configured floor angle")
	contact.grounded = false
	var rejected_angle := deg_to_rad(62.1)
	var rejected_normal := Vector3(sin(rejected_angle), cos(rejected_angle), 0.0)
	contact.merge_capsule_floor(true, rejected_normal, 62.0)
	if contact.grounded:
		failures.append("Contact solver accepted a slope beyond the configured floor angle")

func _test_landing_prediction_cache() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.state = SkierController.State.AIR
	# Spawn now primes presentation and its landing prediction before rendering.
	# Begin a new physics step to test the per-step cache contract.
	skier._physics_step_serial += 1
	var before: int = skier._landing_prediction_evaluations
	skier._predict_landing()
	skier._predict_landing()
	if skier._landing_prediction_evaluations - before != 1:
		failures.append("Landing prediction evaluated more than once within one physics step")
	skier._landing_prediction_cache_serial = -1
	skier._predict_landing()
	if skier._landing_prediction_evaluations - before != 2:
		failures.append("Landing prediction cache did not invalidate for a new physics step")
	remove_child(skier)
	skier.queue_free()

func _test_bail_rest_damping() -> void:
	var profile := SkiPhysicsProfile.new()
	var solver := BailMotionSolver.new()
	var velocity := Vector3(4.0, 0.0, -3.0)
	var angular_velocity := Vector3(0.4, 0.7, -0.2)
	var result := solver.step_motion(
		velocity,
		angular_velocity,
		Vector3.UP,
		true,
		CrashContext.Stage.REST,
		1.0 / 60.0,
		profile
	)
	if result.velocity.length() >= velocity.length() or result.angular_velocity.length() >= angular_velocity.length():
		failures.append("Bail REST motion did not monotonically damp linear and angular velocity")

func _test_fall_rotation_softening_preserves_linear_motion() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var initial_velocity := Vector3(1.2, 0.0, -8.0)
	var initial_angular := Vector3(3.2, 2.8, 4.2)
	for hz: int in [30, 60, 120]:
		var delta := 1.0 / float(hz)
		var velocity := initial_velocity
		var angular := initial_angular
		var basis := Basis.from_euler(Vector3(PI * 0.35, 0.0, PI * 0.22))
		for _index: int in int(hz * 0.5):
			var motion := solver.step_motion(velocity, angular, Vector3.UP, true, CrashContext.Stage.FALL, delta, profile, basis)
			velocity = motion.velocity
			angular = motion.angular_velocity
			basis = solver.integrate_grounded_crash_basis(basis, angular, Vector3.UP, motion.planar_travel, motion.align_rate, delta, profile)
		var expected_velocity := initial_velocity * exp(-profile.bail_ground_damping * 0.55 * 0.5)
		if velocity.distance_to(expected_velocity) > 0.0002:
			failures.append("Softer FALL rotation changed linear slide damping at %d Hz (got %s expected %s)" % [hz, velocity, expected_velocity])
		if angular.length() > 1.8:
			failures.append("High-energy grounded FALL retained %.3f rad/s after 0.5s at %d Hz" % [angular.length(), hz])
		if angular.length() < 0.05:
			failures.append("Softer grounded FALL erased all visible rotational motion at %d Hz" % hz)

func _make_crash_context(incoming: Vector3) -> CrashContext:
	var context := CrashContext.new()
	context.begin(
		CrashContext.Reason.LANDING_IMPACT,
		CrashContext.Source.LANDING,
		SkierController.State.AIR,
		incoming,
		incoming,
		Vector3.UP,
		maxf(0.0, -incoming.y),
		0.8
	)
	return context

func _test_crash_entry_clears_locomotion() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), Vector3(0.0, -1.0, -8.0))
	skier.edge_amount = 0.8
	skier.steering_input = 0.6
	skier.steering_input_raw = 0.6
	skier.pressure_amount = 0.5
	skier.tuck_amount = 0.7
	skier.brake_amount = 0.4
	skier.braking = true
	skier.skid_amount = 0.5
	skier.carve_force = 3.0
	skier.lateral_slip = 1.2
	if not skier.enter_crash(_make_crash_context(skier.velocity)):
		failures.append("Locomotion-clear setup could not enter crash")
	elif skier.edge_amount != 0.0 or skier.steering_input != 0.0 or skier.pressure_amount != 0.0 or skier.tuck_amount != 0.0 or skier.brake_amount != 0.0 or skier.braking or skier.skid_amount != 0.0 or skier.carve_force != 0.0 or skier.lateral_slip != 0.0:
		failures.append("Crash entry retained downhill locomotion channels into BAIL")
	remove_child(skier)
	skier.queue_free()

func _test_grounded_crash_tumbles_gradually() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(2.0, -0.5, -3.0))
	skier.enter_crash(_make_crash_context(skier.velocity))
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_basis = Basis(Vector3.FORWARD, deg_to_rad(20.0))
	skier.angular_velocity = Vector3(0.5, 0.3, 0.4)
	skier.crash_context.set_stage(CrashContext.Stage.FALL)
	var before := skier.global_basis.orthonormalized().get_rotation_quaternion()
	skier._update_bail(1.0 / 60.0)
	var after := skier.global_basis.orthonormalized().get_rotation_quaternion()
	var turn := before.angle_to(after)
	if turn < 0.0005:
		failures.append("Grounded crash did not tumble; bail froze with angular momentum available")
	var max_step := BailMotionSolver.new().grounded_rotation_step_limit(1.0 / 60.0, skier.profile)
	if turn > max_step + 0.0001:
		failures.append("Grounded crash snapped %.1f degrees in one tick instead of staying inside the rotation bound" % rad_to_deg(turn))
	remove_child(skier)
	skier.queue_free()

func _test_bail_collider_stays_surface_aligned() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, 3.0)), Vector3(3.0, -1.0, -6.0))
	skier.enter_crash(_make_crash_context(skier.velocity))
	skier.global_basis = Basis.from_euler(Vector3(1.2, 0.4, -0.8))
	var normal := Vector3(0.22, 0.96, 0.17).normalized()
	if not skier.has_method("_stabilize_bail_collision_shape"):
		failures.append("BAIL has no surface-aligned collision-shape seam; the tumbling root can lever the capsule off snow")
	else:
		skier.call("_stabilize_bail_collision_shape", normal)
		var collision_shape := skier.find_children("*", "CollisionShape3D", true, false).front() as CollisionShape3D
		if collision_shape == null:
			failures.append("BAIL surface-alignment test could not find the production collision shape")
		else:
			var shape_up := collision_shape.global_basis.y.normalized()
			var seat_offset := collision_shape.global_position - skier.global_position
			if shape_up.dot(normal) < 0.999:
				failures.append("BAIL collision capsule followed the tumbling visual root instead of the support normal")
			if absf(seat_offset.dot(normal) - 0.67) > 0.002 or seat_offset.slide(normal).length() > 0.002:
				failures.append("BAIL collision capsule rotated its seat offset away from the support normal")
	remove_child(skier)
	skier.queue_free()

func _test_bail_probe_footprint_stays_on_surface() -> void:
	var solver := SkiContactSolver.new()
	if not solver.has_method("planar_probe_offset"):
		failures.append("BAIL has no orientation-independent contact footprint; tumbling probes can lose snow support")
		return
	var normal := Vector3(0.2, 0.96, 0.1).normalized()
	var tumbling_basis := Basis.from_euler(Vector3(1.3, 0.4, -0.9))
	for offset: Vector3 in SkiPhysicsProfile.new().contact_probe_offsets():
		var stable := solver.call("planar_probe_offset", offset, tumbling_basis, normal, false) as Vector3
		if absf(stable.dot(normal)) > 0.0001:
			failures.append("BAIL contact footprint rotated a probe %.3fm away from the support plane" % absf(stable.dot(normal)))
			break

func _test_rest_waits_for_snow_alignment() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3.ZERO)
	skier.enter_crash(_make_crash_context(Vector3.ZERO))
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_basis = Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5))
	skier.velocity = Vector3.ZERO
	skier.angular_velocity = Vector3.ZERO
	skier.crash_context.elapsed = skier.profile.crash_max_duration
	skier.crash_context.stage_elapsed = skier.profile.crash_max_duration
	skier._update_crash_stage_and_rest(1.0 / 60.0)
	if skier.crash_context.stage != CrashContext.Stage.FALL or skier.crash_context.rest_detected:
		failures.append("Crash entered REST while the root and skis were still side-on to the snow")
	remove_child(skier)
	skier.queue_free()

func _test_surface_roll_axis_on_flat_and_slope() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var flat_travel := Vector3(4.0, 0.0, 0.0)
	var flat_axis := solver.surface_roll_axis(Vector3.UP, flat_travel)
	var expected_flat := Vector3.UP.cross(flat_travel.normalized())
	if flat_axis.distance_to(expected_flat) > 0.001:
		failures.append("Flat-ground roll axis was %s instead of normal × travel %s" % [flat_axis, expected_flat])
	var slope := Vector3(0.4, 1.0, 0.0).normalized()
	var slope_travel := Vector3.FORWARD.slide(slope).normalized() * 6.0
	var slope_axis := solver.surface_roll_axis(slope, slope_travel)
	var expected_slope := slope.cross(slope_travel.normalized())
	if slope_axis.distance_to(expected_slope) > 0.001:
		failures.append("Slope roll axis was %s instead of normal × travel %s" % [slope_axis, expected_slope])
	var stepped := solver.step_motion(slope_travel, Vector3.ZERO, slope, true, CrashContext.Stage.FALL, 1.0 / 60.0, profile)
	if not stepped.roll_valid or stepped.roll_axis.dot(expected_slope) < 0.98:
		failures.append("Grounded FALL step did not publish the slope roll axis")

func _test_surface_roll_reverses_with_travel() -> void:
	var solver := BailMotionSolver.new()
	var forward := solver.surface_roll_axis(Vector3.UP, Vector3(5.0, 0.0, 0.0))
	var backward := solver.surface_roll_axis(Vector3.UP, Vector3(-5.0, 0.0, 0.0))
	if forward.dot(backward) > -0.98:
		failures.append("Reversing planar travel did not reverse the generated roll axis")
	var profile := SkiPhysicsProfile.new()
	var coupled_forward := solver.couple_surface_roll(Vector3.ZERO, Vector3.UP, Vector3(5.0, 0.0, 0.0), Basis.IDENTITY, profile)
	var coupled_backward := solver.couple_surface_roll(Vector3.ZERO, Vector3.UP, Vector3(-5.0, 0.0, 0.0), Basis.IDENTITY, profile)
	if coupled_forward.dot(coupled_backward) >= 0.0:
		failures.append("Reversing planar travel did not reverse generated roll angular velocity")

func _test_surface_roll_grows_with_speed_and_respects_cap() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var slow := solver.surface_roll_speed(0.5, profile)
	var fast := solver.surface_roll_speed(1.0, profile)
	var capped := solver.surface_roll_speed(100.0, profile)
	if slow <= 0.0 or fast <= slow:
		failures.append("Generated roll speed did not grow with planar speed (slow=%.3f fast=%.3f)" % [slow, fast])
	if capped > profile.crash_roll_max_angular_speed + 0.0001:
		failures.append("Generated roll speed %.3f exceeded the configured cap %.3f" % [capped, profile.crash_roll_max_angular_speed])
	var incoming := Vector3(1.2, -0.4, 0.8)
	var coupled := solver.couple_surface_roll(incoming, Vector3.UP, Vector3(8.0, 0.0, 0.0), Basis.IDENTITY, profile)
	var pure_roll := solver.surface_roll_axis(Vector3.UP, Vector3(8.0, 0.0, 0.0)) * profile.crash_roll_max_angular_speed
	if coupled.distance_to(incoming) < 0.001:
		failures.append("Ground-coupled roll did not blend toward the surface-roll component")
	if coupled.distance_to(pure_roll) < 0.001:
		failures.append("Ground-coupled roll replaced incoming crash angular momentum outright")

func _test_zero_speed_does_not_generate_roll() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	if solver.surface_roll_speed(0.0, profile) != 0.0 or solver.surface_roll_speed(0.05, profile) != 0.0:
		failures.append("Near-zero planar speed manufactured a surface-roll rate")
	if solver.surface_roll_axis(Vector3.UP, Vector3(0.01, 0.0, 0.0)) != Vector3.ZERO:
		failures.append("Near-zero travel manufactured a roll axis")
	var incoming := Vector3(0.6, -0.2, 0.4)
	var result := solver.step_motion(Vector3.ZERO, incoming, Vector3.UP, true, CrashContext.Stage.FALL, 1.0 / 60.0, profile)
	if result.roll_valid or result.generated_roll_speed != 0.0:
		failures.append("Zero-speed FALL generated a surface-roll component")
	var expected := incoming * exp(-profile.crash_ground_angular_damping * 0.6 * (1.0 / 60.0))
	if result.angular_velocity.distance_to(expected) > 0.0001:
		failures.append("Zero-speed FALL did not keep the existing damped crash angular velocity")

func _test_travel_direction_sprawl() -> void:
	var layer := CrashReactionLayer.new()
	var profile := SkierAnimationProfile.new()
	var forward := layer.fall_travel_sprawl(_make_sprawl_frame(Vector3(0.0, 0.0, -6.0)), profile)
	var backward := layer.fall_travel_sprawl(_make_sprawl_frame(Vector3(0.0, 0.0, 6.0)), profile)
	var left := layer.fall_travel_sprawl(_make_sprawl_frame(Vector3(-6.0, 0.0, 0.0)), profile)
	var right := layer.fall_travel_sprawl(_make_sprawl_frame(Vector3(6.0, 0.0, 0.0)), profile)
	if not bool(forward.get("valid", false)) or float(forward.get("forward", 0.0)) <= 0.7:
		failures.append("Forward crash travel did not drive a forward FALL sprawl")
	if not bool(backward.get("valid", false)) or float(backward.get("forward", 0.0)) >= -0.7:
		failures.append("Backward crash travel did not drive a backward FALL sprawl")
	if not bool(left.get("valid", false)) or float(left.get("lateral", 0.0)) >= -0.7:
		failures.append("Left crash travel did not drive a left FALL sprawl")
	if not bool(right.get("valid", false)) or float(right.get("lateral", 0.0)) <= 0.7:
		failures.append("Right crash travel did not drive a right FALL sprawl")
	var forward_pelvis := forward.get("pelvis", Vector3.ZERO) as Vector3
	var backward_pelvis := backward.get("pelvis", Vector3.ZERO) as Vector3
	if forward_pelvis.x >= backward_pelvis.x:
		failures.append("Forward travel did not fold the pelvis more than backward travel")
	var left_pelvis := left.get("pelvis", Vector3.ZERO) as Vector3
	var right_pelvis := right.get("pelvis", Vector3.ZERO) as Vector3
	if left_pelvis.z * right_pelvis.z >= 0.0:
		failures.append("Lateral travel did not roll the pelvis with skier-local travel direction")

func _test_degenerate_roll_inputs_remain_finite() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var layer := CrashReactionLayer.new()
	var zero_axis := solver.surface_roll_axis(Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
	var parallel_axis := solver.surface_roll_axis(Vector3.UP, Vector3(0.0, 5.0, 0.0))
	var nan_velocity := Vector3(NAN, 0.0, 0.0)
	var nan_step := solver.step_motion(nan_velocity, Vector3.ONE, Vector3.UP, true, CrashContext.Stage.FALL, 1.0 / 60.0, profile)
	var inf_normal := solver.integrate_grounded_crash_basis(Basis.IDENTITY, Vector3.ONE, Vector3(INF, 0.0, 0.0), Vector3.RIGHT, 6.0, 1.0 / 60.0, profile)
	var degenerate_sprawl := layer.fall_travel_sprawl(_make_sprawl_frame(Vector3.ZERO), SkierAnimationProfile.new())
	if zero_axis != Vector3.ZERO or parallel_axis != Vector3.ZERO:
		failures.append("Degenerate normals or travel manufactured a roll axis")
	if not nan_step.angular_velocity.is_finite() or not nan_step.velocity.is_finite() or nan_step.roll_valid:
		failures.append("Non-finite travel produced a non-finite or invented grounded roll")
	if not inf_normal.x.is_finite() or not inf_normal.y.is_finite() or not inf_normal.z.is_finite():
		failures.append("Invalid ground normal produced a non-finite crash basis")
	if bool(degenerate_sprawl.get("valid", true)) or not (degenerate_sprawl.get("pelvis", Vector3.ONE) as Vector3).is_finite():
		failures.append("Zero-speed sprawl left the FALL pose owner or went non-finite")

func _test_grounded_tumble_respects_rotation_bounds() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	for hz: int in [30, 60, 120]:
		var delta := 1.0 / float(hz)
		var max_step := solver.grounded_rotation_step_limit(delta, profile)
		var proposed := solver.integrate_grounded_crash_basis(
			Basis.IDENTITY,
			Vector3.RIGHT * 40.0,
			Vector3.UP,
			Vector3(12.0, 0.0, 0.0),
			0.0,
			delta,
			profile
		)
		var angle := Basis.IDENTITY.get_rotation_quaternion().angle_to(proposed.get_rotation_quaternion())
		if angle > max_step + 0.0001:
			failures.append("Grounded tumble at %d Hz rotated %.3f rad beyond the %.3f bound" % [hz, angle, max_step])
		skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(12.0, 0.0, 0.0))
		skier.enter_crash(_make_crash_context(skier.velocity))
		skier.contact.grounded = true
		skier.contact.average_normal = Vector3.UP
		skier.angular_velocity = Vector3.RIGHT * 40.0
		skier.crash_context.set_stage(CrashContext.Stage.FALL)
		var before := skier.global_basis.orthonormalized().get_rotation_quaternion()
		skier._update_bail(delta)
		var turn := before.angle_to(skier.global_basis.orthonormalized().get_rotation_quaternion())
		if turn > max_step + 0.0001:
			failures.append("Controller grounded tumble at %d Hz rotated %.3f rad beyond the bound" % [hz, turn])
	remove_child(skier)
	skier.queue_free()

func _test_airborne_bail_continuity_unchanged() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for hz: int in [30, 60, 120]:
		var delta := 1.0 / float(hz)
		for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
			var incoming := axis * 1.0
			var motion := solver.step_motion(Vector3.DOWN, incoming, Vector3.UP, false, CrashContext.Stage.FALL, delta, profile, Basis(axis, deg_to_rad(150.0)))
			var expected_angular := incoming * exp(-profile.crash_air_angular_damping * delta)
			if motion.angular_velocity.distance_to(expected_angular) > 0.000001:
				failures.append("Airborne BAIL angular damping at %d Hz changed (got %s expected %s)" % [hz, motion.angular_velocity, expected_angular])
			if motion.roll_valid or motion.generated_roll_speed != 0.0:
				failures.append("Airborne BAIL manufactured a ground-coupled roll component")
			var initial_basis := Basis(axis, deg_to_rad(150.0))
			skier.reset_for_benchmark(Transform3D(initial_basis, Vector3(0.0, 10.0, 0.0)), Vector3.DOWN)
			skier.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			skier.angular_velocity = incoming
			skier._bail()
			skier.contact.grounded = false
			var before_basis := skier.transform.basis
			skier._update_bail(delta)
			if skier.angular_velocity.distance_to(expected_angular) > 0.000001:
				failures.append("Airborne BAIL controller damping at %d Hz changed" % hz)
			var expected_basis := (
				before_basis
				* Basis(Vector3.RIGHT, expected_angular.x * delta)
				* Basis(Vector3.UP, expected_angular.y * delta)
				* Basis(Vector3.BACK, expected_angular.z * delta)
			).orthonormalized()
			var actual_basis := skier.transform.basis.orthonormalized()
			var turn := expected_basis.get_rotation_quaternion().angle_to(actual_basis.get_rotation_quaternion())
			if turn > 0.002:
				failures.append("Airborne BAIL rotation path at %d Hz diverged from the existing local-axis integration (%.5f rad)" % [hz, turn])
	remove_child(skier)
	skier.queue_free()

func _test_ground_alignment_weakens_with_speed() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var slow := solver.ground_align_rate(CrashContext.Stage.FALL, 0.2, profile)
	var mid := solver.ground_align_rate(CrashContext.Stage.FALL, 3.5, profile)
	var fast := solver.ground_align_rate(CrashContext.Stage.FALL, 20.0, profile)
	var rest := solver.ground_align_rate(CrashContext.Stage.REST, 20.0, profile)
	var recovery := solver.ground_align_rate(CrashContext.Stage.RECOVERY, 20.0, profile)
	if mid > slow + 0.0001 or fast > mid + 0.0001:
		failures.append("Snow alignment strengthened as FALL travel speed increased")
	if rest < slow or recovery < slow:
		failures.append("REST/recovery alignment was weaker than slow FALL alignment")
	if rest < profile.bail_ground_align_rate - 0.0001:
		failures.append("REST alignment did not use the full snow-align rate")

func _test_rest_detection_and_recovery_timing() -> void:
	var solver := BailMotionSolver.new()
	var profile := SkiPhysicsProfile.new()
	var quiet := solver.resolve_rest(true, profile.crash_min_duration, 0.0, 0.0, false, 0.0, profile.crash_rest_confirm_time, 0.18, 0.22, profile)
	if not quiet.rest_detected or quiet.stage != CrashContext.Stage.REST:
		failures.append("Quiet grounded crash no longer confirmed REST")
	var hold := solver.resolve_rest(true, profile.crash_min_duration, 0.0, 0.0, true, 0.0, profile.crash_rest_hold_time, 0.18, 0.22, profile)
	if not hold.should_recover:
		failures.append("REST hold time no longer released recovery")
	var moving := solver.resolve_rest(true, profile.crash_min_duration, profile.crash_rest_speed + 0.5, 0.0, false, 0.05, 1.0 / 60.0, 0.18, 0.22, profile)
	if moving.rest_detected or moving.rest_elapsed != 0.0:
		failures.append("Rest detection confirmed while planar speed was still above the rest threshold")

func _test_crash_severity_duration_bands() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	var soft := CrashContext.new()
	soft.begin(
		CrashContext.Reason.LANDING_IMPACT,
		CrashContext.Source.LANDING,
		SkierController.State.GROUND,
		Vector3(0.0, 0.0, -9.0),
		Vector3(0.0, 0.0, -9.0),
		Vector3.UP,
		0.0,
		0.0
	)
	var medium := CrashContext.new()
	medium.begin(
		CrashContext.Reason.FEATURE_IMPACT,
		CrashContext.Source.OBSTACLE,
		SkierController.State.AIR,
		Vector3(8.0, 0.0, -8.0),
		Vector3(4.0, 0.0, -5.0),
		Vector3.LEFT,
		skier.profile.bail_impact_speed * 0.5,
		skier.profile.maximum_angular_speed * skier.profile.bail_angular_ratio * 0.5,
		0.5
	)
	var severe := CrashContext.new()
	severe.begin(
		CrashContext.Reason.LANDING_ANGULAR,
		CrashContext.Source.LANDING,
		SkierController.State.AIR,
		Vector3(0.0, -16.0, -8.0),
		Vector3(0.0, -8.0, -4.0),
		Vector3.UP,
		skier.profile.bail_impact_speed,
		skier.profile.maximum_angular_speed * skier.profile.bail_angular_ratio,
		1.0
	)
	var soft_deadline := skier.crash_settle_deadline(soft)
	var medium_deadline := skier.crash_settle_deadline(medium)
	var severe_deadline := skier.crash_settle_deadline(severe)
	if not is_equal_approx(soft_deadline, skier.profile.crash_soft_max_duration):
		failures.append("Low-severity crash did not use the short settle deadline")
	if medium_deadline <= soft_deadline or medium_deadline >= severe_deadline:
		failures.append("Medium crash deadline was not between soft and severe budgets")
	if not is_equal_approx(severe_deadline, skier.profile.crash_max_duration):
		failures.append("Severe crash did not retain the full settle deadline")
	remove_child(skier)
	skier.queue_free()

func _test_hybrid_ragdoll_contract() -> void:
	var ragdoll := CrashRagdoll3D.new()
	add_child(ragdoll)
	var profile := SkiPhysicsProfile.new()
	var transforms := _ragdoll_sample_transforms()
	var activated := ragdoll.activate(
		transforms,
		Vector3(2.0, -1.0, -6.0),
		Vector3(0.5, 0.2, 0.8),
		1.0,
		-1.0,
		profile,
		1.0
	)
	var snapshot := ragdoll.snapshot()
	if not activated or not bool(snapshot.active) or int(snapshot.body_count) != 15 or int(snapshot.joint_count) != 10:
		failures.append("Hybrid ragdoll did not build the expected bounded physical skeleton")
	if not bool(snapshot.left_ski_released) or not bool(snapshot.right_ski_released) or not bool(snapshot.left_pole_released):
		failures.append("Major crash did not release skis and poles at the configured thresholds")
	var pose := ragdoll.physics_pose()
	if pose.size() < 20 or not (pose.get(&"pelvis", Transform3D.IDENTITY) as Transform3D).origin.is_finite():
		failures.append("Hybrid ragdoll did not expose a finite full-body presentation pose")
	for body_value: Variant in ragdoll.bodies.values():
		var body := body_value as RigidBody3D
		if body == null:
			continue
		if body.collision_layer != CollisionLayers.RAGDOLL or body.collision_mask != CollisionLayers.WORLD_SOLID_MASK:
			failures.append("Hybrid ragdoll body escaped the shared collision-layer ABI")
			break
		if not body.continuous_cd:
			failures.append("Hybrid ragdoll body disabled continuous collision detection")
			break
	if not is_finite(float(snapshot.get("joint_error", NAN))):
		failures.append("Hybrid ragdoll did not expose a finite joint anchor error")
	for semantic: StringName in [&"pelvis", &"left_hand", &"right_boot", &"head"]:
		if not pose.has(semantic):
			continue
		var expected := transforms[semantic] as Transform3D
		if (pose[semantic] as Transform3D).origin.distance_to(expected.origin) > 0.001:
			failures.append("Hybrid ragdoll pose round-trip drifted at %s" % semantic)
	var soft := _activate_ragdoll_sample(ragdoll, transforms, profile, 0.2, 0.2, 0.0)
	if int(soft.get("body_count", 0)) != 11 or bool(soft.get("left_ski_released", true)) or bool(soft.get("left_pole_released", true)):
		failures.append("Soft crash released equipment before the configured thresholds")
	var one_side := _activate_ragdoll_sample(ragdoll, transforms, profile, 0.6, 0.6, -1.0)
	if int(one_side.get("body_count", 0)) != 14 or not bool(one_side.get("left_ski_released", false)) or bool(one_side.get("right_ski_released", true)):
		failures.append("Single-ski release did not follow the lateral bias")
	var both := _activate_ragdoll_sample(ragdoll, transforms, profile, 0.9, 0.9, 1.0)
	if int(both.get("body_count", 0)) != 15 or not bool(both.get("right_pole_released", false)):
		failures.append("Severe crash did not release all equipment")
	var incomplete := CrashRagdoll3D.new()
	add_child(incomplete)
	var partial := transforms.duplicate()
	partial.erase(&"head")
	if incomplete.activate(partial, Vector3(1.0, 0.0, -2.0), Vector3.ZERO, 0.5, 0.0, profile, 0.5):
		failures.append("Hybrid ragdoll accepted a pose missing a required body transform")
	if bool(incomplete.snapshot().active) or not incomplete.bodies.is_empty():
		failures.append("Rejected hybrid ragdoll retained physical bodies")
	remove_child(incomplete)
	incomplete.queue_free()
	ragdoll.begin_recovery()
	if not bool(ragdoll.snapshot().recovering):
		failures.append("Hybrid ragdoll did not freeze into the recovery blend")
	var frozen_pose := ragdoll.physics_pose()
	if frozen_pose != ragdoll.physics_pose():
		failures.append("Hybrid ragdoll recovery pose changed after the freeze")
	ragdoll.stop()
	if bool(ragdoll.snapshot().active):
		failures.append("Hybrid ragdoll retained physics ownership after cleanup")
	remove_child(ragdoll)
	ragdoll.queue_free()

func _test_ragdoll_telemetry_contract() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(2.0, -1.0, -6.0))
	skier.enter_crash(_make_crash_context(skier.velocity))
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier._update_ragdoll_presentation()
	if skier.crash_ragdoll == null or not skier.crash_ragdoll.active:
		failures.append("Ragdoll telemetry fixture could not activate the crash proxy")
	else:
		var ragdoll_telemetry := skier._crash_telemetry_snapshot().get("ragdoll", {}) as Dictionary
		if not is_finite(float(ragdoll_telemetry.get("joint_error", NAN))):
			failures.append("Crash telemetry lost the finite ragdoll joint error")
		if not is_finite(float(ragdoll_telemetry.get("carrier_speed", NAN))) or not is_finite(float(ragdoll_telemetry.get("slip_speed", NAN))):
			failures.append("Crash telemetry lost finite carrier and pelvis slip speeds")
	remove_child(skier)
	skier.queue_free()

func _ragdoll_sample_transforms() -> Dictionary:
	return {
		&"pelvis": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)),
		&"spine": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.22, 0.0)),
		&"chest": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.55, 0.0)),
		&"head": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.92, 0.0)),
		&"left_hip": Transform3D(Basis.IDENTITY, Vector3(-0.14, 0.96, 0.0)),
		&"left_knee": Transform3D(Basis.IDENTITY, Vector3(-0.14, 0.50, 0.0)),
		&"left_boot": Transform3D(Basis.IDENTITY, Vector3(-0.14, 0.08, -0.03)),
		&"right_hip": Transform3D(Basis.IDENTITY, Vector3(0.14, 0.96, 0.0)),
		&"right_knee": Transform3D(Basis.IDENTITY, Vector3(0.14, 0.50, 0.0)),
		&"right_boot": Transform3D(Basis.IDENTITY, Vector3(0.14, 0.08, -0.03)),
		&"left_shoulder": Transform3D(Basis.IDENTITY, Vector3(-0.32, 1.58, 0.0)),
		&"left_elbow": Transform3D(Basis.IDENTITY, Vector3(-0.62, 1.34, 0.0)),
		&"left_hand": Transform3D(Basis.IDENTITY, Vector3(-0.82, 1.08, 0.0)),
		&"right_shoulder": Transform3D(Basis.IDENTITY, Vector3(0.32, 1.58, 0.0)),
		&"right_elbow": Transform3D(Basis.IDENTITY, Vector3(0.62, 1.34, 0.0)),
		&"right_hand": Transform3D(Basis.IDENTITY, Vector3(0.82, 1.08, 0.0)),
		&"left_ski": Transform3D(Basis.IDENTITY, Vector3(-0.14, 0.0, -0.08)),
		&"right_ski": Transform3D(Basis.IDENTITY, Vector3(0.14, 0.0, -0.08)),
		&"left_pole": Transform3D(Basis.IDENTITY, Vector3(-0.82, 1.08, 0.0)),
		&"right_pole": Transform3D(Basis.IDENTITY, Vector3(0.82, 1.08, 0.0)),
		&"left_pole_tip": Transform3D(Basis.IDENTITY, Vector3(-0.9, -0.08, 0.1)),
		&"right_pole_tip": Transform3D(Basis.IDENTITY, Vector3(0.9, -0.08, 0.1)),
	}

func _activate_ragdoll_sample(
	ragdoll: CrashRagdoll3D,
	transforms: Dictionary,
	profile: SkiPhysicsProfile,
	crash_severity: float,
	binding_severity: float,
	lateral_bias: float
) -> Dictionary:
	if not ragdoll.activate(
		transforms,
		Vector3(1.0, 0.0, -2.0),
		Vector3(0.1, 0.2, 0.3),
		crash_severity,
		lateral_bias,
		profile,
		binding_severity
	):
		return {}
	return ragdoll.snapshot()

func _test_ragdoll_ground_and_joint_stability() -> void:
	var floor_body := _make_box_body("RagdollFloor", 1, Vector3(40.0, 0.5, 40.0), Vector3(0.0, -0.25, 0.0))
	var ragdoll := CrashRagdoll3D.new()
	add_child(ragdoll)
	var profile := SkiPhysicsProfile.new()
	var activated := ragdoll.activate(
		_ragdoll_sample_transforms(),
		Vector3(3.0, -2.0, -6.0),
		Vector3(0.4, 0.1, 0.6),
		0.3,
		0.0,
		profile,
		0.3
	)
	if not activated or not bool(ragdoll.snapshot().get("active", false)):
		failures.append("Ragdoll stability fixture could not activate the proxy")
	else:
		var maximum_error := 0.0
		var first_half_max := 0.0
		var second_half_max := 0.0
		var samples := 240
		for index: int in samples:
			await get_tree().physics_frame
			var error := ragdoll.maximum_joint_error()
			if not is_finite(error):
				failures.append("Ragdoll joint error became non-finite during simulation")
				break
			maximum_error = maxf(maximum_error, error)
			if index * 2 < samples:
				first_half_max = maxf(first_half_max, error)
			else:
				second_half_max = maxf(second_half_max, error)
		print("RAGDOLL_JOINT_ERROR max=%.4f first=%.4f second=%.4f" % [maximum_error, first_half_max, second_half_max])
		if maximum_error > 0.08:
			failures.append("Ragdoll joint anchors separated beyond tolerance (%.4f)" % maximum_error)
		if second_half_max > first_half_max + 0.02:
			failures.append("Ragdoll joint error grew across the settling window")
		if not ragdoll.has_ground_support():
			failures.append("Settled ragdoll did not report ground support above the floor")
		ragdoll.begin_recovery()
		var frozen := ragdoll.physics_pose()
		await get_tree().physics_frame
		if ragdoll.physics_pose() != frozen:
			failures.append("Ragdoll recovery pose drifted after the freeze")
		ragdoll.stop()
	remove_child(ragdoll)
	ragdoll.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _make_sprawl_frame(velocity: Vector3) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 3
	frame.crash_stage = CrashContext.Stage.FALL
	frame.crash_current_velocity = velocity
	frame.crash_incoming_velocity = velocity
	frame.ground_normal = Vector3.UP
	frame.crash_impact_normal = Vector3.UP
	frame.body_up = Vector3.UP
	frame.body_up_valid = true
	frame.ski_forward = Vector3.FORWARD
	frame.ski_forward_valid = true
	frame.grounded = false
	return frame

func _test_crash_settling_shows_low_speed_motion() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3.ZERO)
	skier.enter_crash(_make_crash_context(Vector3.ZERO))
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.velocity = Vector3.ZERO
	skier.angular_velocity = Vector3.ZERO
	skier.crash_context.current_velocity = Vector3.ZERO
	skier.crash_context.set_stage(CrashContext.Stage.FALL)
	skier._update_animation(1.0 / 60.0)
	var fall_first: Vector3 = skier.animation_controller.debug_snapshot().get("pelvis_rotation", Vector3.ZERO)
	skier.crash_context.advance(1.0 / 60.0)
	skier._update_animation(1.0 / 60.0)
	var fall_second: Vector3 = skier.animation_controller.debug_snapshot().get("pelvis_rotation", Vector3.ZERO)
	if fall_first.distance_to(fall_second) < 0.00005:
		failures.append("Low-speed FALL presented a frozen pose instead of secondary settle motion")
	skier.crash_context.set_stage(CrashContext.Stage.REST)
	skier._update_animation(1.0 / 60.0)
	var rest_first: Vector3 = skier.animation_controller.debug_snapshot().get("spine_rotation", Vector3.ZERO)
	skier.crash_context.advance(1.0 / 60.0)
	skier._update_animation(1.0 / 60.0)
	var rest_second: Vector3 = skier.animation_controller.debug_snapshot().get("spine_rotation", Vector3.ZERO)
	if rest_first.distance_to(rest_second) < 0.00002:
		failures.append("Low-speed REST presented a frozen pose instead of decaying wobble")
	remove_child(skier)
	skier.queue_free()

func _test_recovery_is_rate_limited_and_coordinated() -> void:
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(3.0, -0.5, -4.0))
	var incoming_speed := skier.velocity.slide(Vector3.UP).length()
	skier.enter_crash(_make_crash_context(skier.velocity))
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	skier.global_basis = Basis(Vector3.FORWARD, deg_to_rad(30.0))
	# Simulate stale channels if any path reintroduces them before recovery.
	skier.edge_amount = 0.7
	skier.steering_input = 0.5
	var before := skier.global_basis.orthonormalized().get_rotation_quaternion()
	skier._recover_from_bail(1.0 / 60.0)
	var after := skier.global_basis.orthonormalized().get_rotation_quaternion()
	if before.angle_to(after) > 0.08:
		failures.append("Recovery snapped the root instead of rate-limited realignment")
	if skier.state != SkierController.State.GROUND:
		failures.append("Recovery did not return to grounded skiing")
	if skier.edge_amount != 0.0 or skier.steering_input != 0.0:
		failures.append("Recovery retained stale locomotion into the first grounded frames")
	if skier.angular_velocity.length() > 0.001:
		failures.append("Recovery retained crash angular velocity into skiing")
	var expected_speed := incoming_speed * skier.profile.bail_recovery_speed_retain
	if absf(skier.velocity.length() - expected_speed) > 0.05:
		failures.append("Recovery did not preserve the configured post-crash speed retention")
	if skier.landing_orientation_duration <= 0.0:
		failures.append("Recovery did not seed ground orientation settle for the remaining alignment")
	if bool((skier.telemetry().crash as Dictionary).active):
		failures.append("Recovery retained active crash state")
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
	var stages_seen: Dictionary = {}
	var equipment_failure_reported := false
	var recovery_frames := 0
	var previous_stage := "NONE"
	while skier.state == SkierController.State.BAIL and frames < 420:
		await get_tree().physics_frame
		frames += 1
		var crash := skier.telemetry().crash as Dictionary
		var stage := str(crash.get("stage", "NONE"))
		stages_seen[stage] = true
		if stage == "RECOVERY":
			recovery_frames += 1
		if stage != previous_stage and previous_stage != "NONE" and float(crash.get("stage_elapsed", 999.0)) > 0.05:
			failures.append("Crash stage-local clock did not reset at %s handoff" % stage)
		if stage != previous_stage and stage != "NONE" and skier.animation_controller._crash_stage_progress > 0.1:
			failures.append("Real crash lifecycle jumped presentation progress at %s handoff" % stage)
		previous_stage = stage
		var equipment := skier.telemetry().crash_equipment as Dictionary
		if not equipment_failure_reported and (not bool(equipment.get("valid", false)) or not bool(equipment.get("ski_separation_in_range", false)) or not bool(equipment.get("poles_attached", false))):
			failures.append("Crash equipment lost calibrated attachment during %s stage" % stage)
			equipment_failure_reported = true
	if skier.state != SkierController.State.GROUND:
		failures.append("Low-speed crash did not reach bounded rest and recover")
	if frames < 20:
		failures.append("Crash recovered before a readable minimum crash duration")
	if bool((skier.telemetry().crash as Dictionary).active):
		failures.append("In-place recovery retained active crash state")
	if recovery_frames < 20:
		failures.append("Recovery did not remain in BAIL long enough for a continuous get-up")
	if int(skier.telemetry().respawn_count) != 0:
		failures.append("Ordinary in-place recovery incorrectly used the respawn path")
	for expected_stage: String in ["RELEASE", "IMPACT", "FALL", "REST", "RECOVERY"]:
		if not stages_seen.has(expected_stage):
			failures.append("Crash lifecycle never exposed %s equipment stage" % expected_stage)
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

func _test_airborne_bail_timeout_respawns() -> void:
	SessionManager.clear_marker()
	var skier := SkierController.new()
	add_child(skier)
	skier.reset_for_benchmark(Transform3D(Basis.IDENTITY, Vector3(0.0, 20.0, 0.0)), Vector3.ZERO)
	var context := CrashContext.new()
	context.begin(
		CrashContext.Reason.LANDING_IMPACT,
		CrashContext.Source.LANDING,
		SkierController.State.AIR,
		Vector3.ZERO,
		Vector3.ZERO,
		Vector3.UP,
		0.0,
		0.0
	)
	var initial_respawn_count := int(skier.telemetry().respawn_count)
	if not skier.enter_crash(context):
		failures.append("Airborne timeout setup could not enter crash")
	var frames := 0
	while skier.state == SkierController.State.BAIL and frames < 420:
		await get_tree().physics_frame
		frames += 1
	if skier.state != SkierController.State.AIR:
		failures.append("Airborne bail did not terminate through the respawn path")
	if int(skier.telemetry().respawn_count) != initial_respawn_count + 1:
		failures.append("Airborne bail timeout did not request exactly one respawn")
	if bool((skier.telemetry().crash as Dictionary).active):
		failures.append("Airborne bail timeout retained crash state after respawn")
	remove_child(skier)
	skier.queue_free()

func _test_airborne_contact_normal_refresh() -> void:
	var floor_body := _make_box_body("ContactNormalFloor", 1, Vector3(30.0, 0.5, 30.0), Vector3(0.0, -0.25, 0.0))
	var skier := SkierController.new()
	add_child(skier)
	skier.set_physics_process(false)
	await get_tree().physics_frame
	skier.global_position = Vector3(0.0, 1.2, 0.0)
	skier.contact.average_normal = Vector3.RIGHT
	skier.contact.last_normal = Vector3.UP
	skier.contact.sample(skier, 1.45, 0.5, [], 0.35)
	if skier.contact.grounded:
		failures.append("Above-band contact test unexpectedly became grounded")
	if skier.contact.average_normal.distance_to(Vector3.UP) > 0.001:
		failures.append("Airborne contact retained a stale average normal after a valid hit")
	skier.global_position = Vector3(0.0, 10.0, 0.0)
	skier.contact.average_normal = Vector3.RIGHT
	skier.contact.last_normal = Vector3.UP
	skier.contact.sample(skier, 1.45, 0.5, [], 0.35)
	if skier.contact.average_normal.distance_to(Vector3.UP) > 0.001:
		failures.append("Airborne contact retained a stale average normal after no hit")
	if skier.contact.last_normal.distance_to(Vector3.UP) > 0.001:
		failures.append("No-hit contact sampling corrupted the probe fallback normal")
	remove_child(skier)
	skier.queue_free()
	remove_child(floor_body)
	floor_body.queue_free()

func _test_grind_feature_collision_enters_bail() -> void:
	var path := Curve3D.new()
	path.add_point(Vector3(-2.0, 2.0, 0.0))
	path.add_point(Vector3(4.0, 2.0, 0.0))
	var rail := GrindRail3D.new()
	rail.name = "RegressionRail"
	rail.path = path
	rail.rail_type = GrindRail3D.RailType.BOX
	add_child(rail)
	var obstacle := _make_box_body("GrindObstacle", 4, Vector3(0.4, 4.0, 2.0), Vector3(0.0, 2.2, 0.0))
	var skier := SkierController.new()
	add_child(skier)
	await get_tree().physics_frame
	skier.global_position = rail.sample_world(0.05)
	skier.global_basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP)
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.state = SkierController.State.GRIND
	skier.active_rail = rail
	skier.rail_offset = 0.05
	skier.rail_direction = 1.0
	skier.rail_speed = 12.0
	var frames := 0
	while skier.state == SkierController.State.GRIND and frames < 180:
		await get_tree().physics_frame
		frames += 1
	if skier.state != SkierController.State.BAIL:
		failures.append("GRIND feature impact did not enter crash state")
	else:
		var crash := skier.telemetry().crash as Dictionary
		if str(crash.get("source", "")) != "OBSTACLE" or int(crash.get("source_state", -1)) != SkierController.State.GRIND:
			failures.append("GRIND feature impact lost obstacle/source-state context")
		if int(crash.get("collision_layer", 0)) & 4 == 0:
			failures.append("GRIND feature impact did not retain Features-layer diagnostics")
	remove_child(skier)
	skier.queue_free()
	remove_child(obstacle)
	obstacle.queue_free()
	remove_child(rail)
	rail.queue_free()

func _test_recovery_freeze_ignores_session_input() -> void:
	var skier := SkierController.new()
	skier.set_physics_process(false)
	add_child(skier)
	await get_tree().physics_frame
	SessionManager.clear_marker()
	var spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 6.0, 0.0))
	SessionManager.set_default_spawn(spawn)
	var stay_put := Vector3(5.0, 4.0, 5.0)
	skier.global_position = stay_put
	var count_before := int(skier.telemetry().respawn_count)
	skier.set_recovery_frozen(true)
	Input.action_press("respawn")
	skier._physics_process(1.0 / 60.0)
	Input.action_release("respawn")
	if int(skier.telemetry().respawn_count) != count_before:
		failures.append("Recovery freeze still honored a respawn input")
	if skier.global_position.distance_to(stay_put) > 0.05:
		failures.append("Recovery freeze respawn input moved the skier")
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	Input.action_press("set_marker")
	skier._physics_process(1.0 / 60.0)
	Input.action_release("set_marker")
	if SessionManager.has_marker:
		failures.append("Recovery freeze still saved a marker")
		SessionManager.clear_marker()
	skier.set_recovery_frozen(false)
	remove_child(skier)
	skier.queue_free()

func _test_marker_retry_scoring_policy() -> void:
	await get_tree().process_frame
	var skier := SkierController.new()
	skier.set_physics_process(false)
	add_child(skier)
	var marker := Transform3D(Basis.IDENTITY, Vector3(3.0, 6.0, -4.0))
	SessionManager.set_marker(marker)
	skier.scoring.accept_trick("Baseline 360", 1000, 0.9, LandingSolver.Outcome.CLEAN)
	skier.scoring.accept_trick("Follow-up 180", 100, 0.9, LandingSolver.Outcome.CLEAN)
	var before := skier.scoring.snapshot()
	var expected_cost := int(round(float(before.total_score) * 0.15))
	SessionManager.request_respawn()
	var after := skier.scoring.snapshot()
	if int(after.total_score) != maxi(0, int(before.total_score) - expected_cost):
		failures.append("Explicit marker retry did not apply the configured retry score cost")
	if int(after.retry_count) != int(before.retry_count) + 1 or str(after.last_combo_break_reason) != "marker_retry":
		failures.append("Explicit marker retry did not record exactly one marker retry")
	if str(after.best_trick_name) != str(before.best_trick_name) or int(after.landed_trick_count) != int(before.landed_trick_count):
		failures.append("Explicit marker retry discarded persistent run scoring history")
	if int(after.combo_count) != 0 or float(after.link_remaining) > 0.001:
		failures.append("Explicit marker retry retained transient combo/link state")
	if skier.global_position.distance_to(marker.origin) > 0.05:
		failures.append("Explicit marker retry did not return the skier to the saved marker")
	SessionManager.clear_marker()
	remove_child(skier)
	skier.queue_free()

func _test_course_recovery_lifecycle_and_scoring() -> void:
	await get_tree().process_frame
	var skier := SkierController.new()
	skier.set_physics_process(false)
	add_child(skier)
	var previous_spawn := SessionManager.default_spawn
	SessionManager.set_default_spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.0, 0.0)))
	var marker := Transform3D(Basis.IDENTITY, Vector3(4.0, 6.0, -3.0))
	SessionManager.set_marker(marker)
	skier.scoring.begin_feature("jump")
	skier.scoring.accept_trick("Recovery Baseline", 1000, 0.9, LandingSolver.Outcome.CLEAN)
	var score_before := skier.scoring.snapshot()
	var recovery := CourseRecovery.new()
	recovery.recovery_delay = 0.0
	recovery.fade_out_duration = 0.0
	recovery.fade_in_duration = 0.0
	add_child(recovery)
	recovery.set_target(skier)
	var started := [0]
	var completed := [0]
	recovery.recovery_started.connect(func(_reason: String) -> void: started[0] += 1)
	recovery.recovery_completed.connect(func(_reason: String, _transform: Transform3D) -> void: completed[0] += 1)
	# Let the newly-added recovery node join the physics scheduler before
	# triggering the out-of-bounds transition.
	await get_tree().process_frame
	skier.global_position = Vector3(100.0, 4.0, 0.0)
	var frame_budget := 30
	while completed[0] < 1 and frame_budget > 0:
		await get_tree().physics_frame
		frame_budget -= 1
	# Observe beyond completion so duplicate recovery events cannot hide behind
	# an early event-driven exit.
	for _frame: int in 2:
		await get_tree().physics_frame
	if started[0] != 1 or completed[0] != 1 or recovery.recovery_count != 1:
		failures.append(
			"Course recovery did not emit exactly one start/completion lifecycle (started=%s completed=%s count=%s)"
			% [started[0], completed[0], recovery.recovery_count]
		)
	if recovery.recovery_in_progress or skier.recovery_frozen:
		failures.append("Course recovery remained frozen after completion")
	if skier.global_position.distance_to(marker.origin) > 0.05:
		failures.append("Course recovery did not return the skier to the saved marker")
	var score_after := skier.scoring.snapshot()
	if (
		int(score_after.total_score) != int(score_before.total_score)
		or str(score_after.best_trick_name) != str(score_before.best_trick_name)
		or int(score_after.landed_trick_count) != int(score_before.landed_trick_count)
		or int(score_after.retry_count) != int(score_before.retry_count)
	):
		failures.append("Course recovery changed persistent run scoring or retry state")
	if int(score_after.combo_count) != 0 or float(score_after.link_remaining) > 0.001 or str(score_after.last_combo_break_reason) != "respawn":
		failures.append("Course recovery did not clear transient combo/link state without a retry penalty")
	SessionManager.clear_marker()
	SessionManager.set_default_spawn(previous_spawn)
	remove_child(recovery)
	recovery.queue_free()
	remove_child(skier)
	skier.queue_free()

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
