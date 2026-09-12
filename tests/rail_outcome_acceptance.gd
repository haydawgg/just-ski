extends Node

var failures: Array[String] = []
var outcomes: Array[Dictionary] = []
var content_events: Array[StringName] = []
var skier: SkierController
var rail: GrindRail3D
var content: ParkContentTracker

func _ready() -> void:
	skier = SkierController.new()
	skier.set_physics_process(false)
	add_child(skier)
	rail = GrindRail3D.new()
	rail.name = "OutcomeRail"
	rail.path = Curve3D.new()
	rail.path.add_point(Vector3.ZERO)
	rail.path.add_point(Vector3(0.0, 0.5, -12.0))
	rail.set_meta("feature_id", &"outcome_rail")
	add_child(rail)
	content = ParkContentTracker.new()
	add_child(content)
	content.telemetry_enabled = false
	content.content_event_recorded.connect(func(event: Dictionary) -> void:
		content_events.append(StringName(event.get("kind", &"")))
	)
	content.configure(ParkCourseProfile.new(), skier)
	skier.rail_finished.connect(func(feature_id: StringName, outcome: StringName) -> void:
		outcomes.append({"feature_id": feature_id, "outcome": outcome})
	)
	_validate_success_exit()
	_validate_slip_failure()
	_validate_crash_failure()
	_validate_respawn_cancellation(SessionManager.RESPAWN_SESSION, "marker retry")
	_validate_respawn_cancellation(SessionManager.RESPAWN_SUMMIT_RESTART, "summit restart")
	_validate_respawn_cancellation(SessionManager.RESPAWN_NEW_RUN_MARKER, "new run marker")
	_validate_respawn_cancellation(SessionManager.RESPAWN_COURSE_RECOVERY, "course recovery")
	_validate_content_semantics()
	_report()

func _prime_grind() -> void:
	skier.active_rail = rail
	skier.rail_offset = 4.0
	skier.rail_direction = 1.0
	skier.rail_speed = 10.0
	skier.rail_balance = 0.0
	skier.rail_balance_velocity = 0.0
	skier._rail_stall_time = 0.0
	skier.state = SkierController.State.GRIND
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.state_changed.emit("Grind")

func _assert_single_outcome(expected: StringName, label: String) -> void:
	if outcomes.size() != 1:
		failures.append("%s produced %d rail outcomes instead of 1" % [label, outcomes.size()])
		outcomes.clear()
		return
	var outcome: Dictionary = outcomes[0]
	if StringName(outcome.get("outcome", &"")) != expected:
		failures.append("%s produced outcome %s instead of %s" % [label, str(outcome.get("outcome", &"")), str(expected)])
	if StringName(outcome.get("feature_id", &"")) != &"outcome_rail":
		failures.append("%s carried the wrong rail feature id (%s)" % [label, str(outcome.get("feature_id", &""))])
	outcomes.clear()

func _validate_success_exit() -> void:
	_prime_grind()
	skier._exit_rail(false)
	_assert_single_outcome(&"success", "Normal rail exit")
	if skier.state != SkierController.State.AIR or skier.active_rail != null:
		failures.append("Normal rail exit did not release rail ownership into AIR")

func _validate_slip_failure() -> void:
	_prime_grind()
	skier.rail_balance = 0.8
	skier.rail_balance_velocity = -2.0
	skier._slip_off_rail()
	_assert_single_outcome(&"failed", "Balance slip")
	if skier.state != SkierController.State.AIR or skier.active_rail != null:
		failures.append("Balance slip did not release rail ownership into AIR")

func _validate_crash_failure() -> void:
	_prime_grind()
	var crash := CrashContext.new()
	crash.begin(
		CrashContext.Reason.FEATURE_IMPACT,
		CrashContext.Source.RAIL,
		2,
		Vector3(0.0, 0.0, -8.0),
		Vector3.ZERO,
		Vector3.UP,
		8.0,
		1.0
	)
	skier.enter_crash(crash)
	_assert_single_outcome(&"failed", "Grind collision crash")
	if skier.state != SkierController.State.BAIL or skier.active_rail != null:
		failures.append("Grind collision crash did not enter BAIL without the rail")

func _validate_respawn_cancellation(reason: StringName, label: String) -> void:
	SessionManager.set_marker(Transform3D(Basis.IDENTITY, Vector3(3.0, 6.0, -4.0)))
	_prime_grind()
	match reason:
		SessionManager.RESPAWN_SESSION:
			SessionManager.request_respawn()
		SessionManager.RESPAWN_SUMMIT_RESTART:
			SessionManager.request_summit_restart()
		SessionManager.RESPAWN_NEW_RUN_MARKER:
			SessionManager.request_new_run_from_marker()
		SessionManager.RESPAWN_COURSE_RECOVERY:
			SessionManager.request_respawn_to(skier.global_transform, SessionManager.RESPAWN_COURSE_RECOVERY)
	_assert_single_outcome(&"cancelled", label)
	if skier.state != SkierController.State.AIR or skier.active_rail != null:
		failures.append("%s did not release rail ownership into AIR" % label)
	SessionManager.clear_marker()

func _validate_content_semantics() -> void:
	var rail_results := content_events.count(&"rail_result")
	var rail_cancellations := content_events.count(&"rail_cancelled")
	var rail_exits := content_events.count(&"rail_exit")
	var rail_captures := content_events.count(&"rail_capture")
	if rail_captures != 7:
		failures.append("Content tracker observed %d rail captures instead of 7" % rail_captures)
	if rail_results != 3:
		failures.append("Content tracker observed %d rail results instead of 3" % rail_results)
	if rail_exits != 3:
		failures.append("Content tracker observed %d rail exits instead of 3" % rail_exits)
	if rail_cancellations != 4:
		failures.append("Content tracker observed %d rail cancellations instead of 4" % rail_cancellations)
	for index: int in content_events.size():
		if content_events[index] == &"rail_cancelled" and index + 1 < content_events.size() and content_events[index + 1] == &"rail_result":
			failures.append("A cancelled rail was followed by a rail result event")

func _report() -> void:
	SessionManager.clear_marker()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("RAIL_OUTCOME_PASS: explicit rail success, failure, and cancellation outcomes are emitted exactly once")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RAIL_OUTCOME_FAIL: " + failure)
	get_tree().quit(1)
