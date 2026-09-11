extends Node

const GAMEPLAY_KEYS: Array[String] = [
	"speed_mps", "state", "grounded", "snow_contact", "rail_balance", "rail_progress",
	"predicted_landing_time", "predicted_landing_valid", "landing_feedback_armed",
	"landing_cue", "scoring", "collision_count", "speed_discontinuity", "flick",
]
const DEBUG_ONLY_KEYS: Array[String] = [
	"animation", "crash", "crash_equipment", "steering_raw", "steering", "effective_steer_rate",
	"brake_amount", "skid_amount", "carve_ratio", "available_grip", "centripetal_demand",
	"heading_travel_angle_degrees", "slope_angle_degrees", "surface", "surface_class",
	"surface_normal", "edge", "pressure", "lateral_slip", "carve_force", "angular_velocity",
	"trick_rotation", "rail", "rail_distance_to_end", "rail_entry_severity", "rail_pose",
	"spawn_settle_active", "landing", "collision_colliders", "collision_diagnostics",
	"contact_confidence", "speed_kph", "upright_dot", "line_link", "respawn_count", "recovery_frozen",
]
const SAMPLE_COUNT := 400

var failures: Array[String] = []

func _ready() -> void:
	var skier := SkierController.new()
	skier.set_physics_process(false)
	add_child(skier)
	var gameplay: Dictionary = skier.gameplay_telemetry()
	for key: String in GAMEPLAY_KEYS:
		if not gameplay.has(key):
			failures.append("Gameplay telemetry is missing the HUD/observer key %s" % key)
	for key: String in DEBUG_ONLY_KEYS:
		if gameplay.has(key):
			failures.append("Per-tick gameplay telemetry leaked the debug-only key %s" % key)
	if gameplay.has("animation"):
		failures.append("Gameplay telemetry still builds the animation debug snapshot")
	var landing_cue: Dictionary = gameplay.get("landing_cue", {})
	for key: String in ["readiness_valid", "ready", "pre_bail_weight"]:
		if not landing_cue.has(key):
			failures.append("Landing cue payload is missing %s" % key)
	if landing_cue.size() != 3:
		failures.append("Landing cue payload grew to %d keys; the cue must stay narrow" % landing_cue.size())
	var flick: Dictionary = gameplay.get("flick", {})
	for key: String in ["grab_qualified", "live_grab", "kind", "yaw_degrees", "flip_degrees", "cork_degrees"]:
		if not flick.has(key):
			failures.append("Flick payload is missing the challenge observer key %s" % key)
	var scoring: Dictionary = gameplay.get("scoring", {})
	for key: String in ["total_score", "combo_count", "combo_remaining", "combo_window"]:
		if not scoring.has(key):
			failures.append("Scoring payload is missing the HUD key %s" % key)
	# The full debug snapshot stays available on demand and remains strictly
	# larger to build than the per-tick payload.
	var full: Dictionary = skier.telemetry()
	for key: String in DEBUG_ONLY_KEYS:
		if not full.has(key):
			failures.append("Full debug telemetry lost the key %s" % key)
	var gameplay_micros := _measure(skier, true)
	var full_micros := _measure(skier, false)
	print("TELEMETRY_BUDGET gameplay=%.2f us full=%.2f us ratio=%.2fx" % [gameplay_micros, full_micros, full_micros / maxf(gameplay_micros, 0.001)])
	if full_micros < 2.5 * gameplay_micros:
		failures.append(
			"Full debug telemetry is not meaningfully more expensive than the per-tick payload (%.2f vs %.2f us)"
			% [full_micros, gameplay_micros]
		)
	skier.queue_free()
	if failures.is_empty():
		print("DEBUG_TELEMETRY_BUDGET_PASS: hidden diagnostics build no debug snapshots or debug formatting at tick rate")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("DEBUG_TELEMETRY_BUDGET_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _measure(skier: SkierController, gameplay: bool) -> float:
	# Warm both paths so first-call setup does not skew either measurement.
	if gameplay:
		skier.gameplay_telemetry()
	else:
		skier.telemetry()
	var start := Time.get_ticks_usec()
	for _index: int in SAMPLE_COUNT:
		if gameplay:
			skier.gameplay_telemetry()
		else:
			skier.telemetry()
	return float(Time.get_ticks_usec() - start) / float(SAMPLE_COUNT)
