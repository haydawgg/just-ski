extends Node

## Phase 13 high-speed linked-carve stress: sustained alternating carves on the
## production resort with camera and stance telemetry. Proves the integrated
## carve path keeps the camera band, hard-frame validity, readable loading, and
## a modest mirrored turn lead without state lock or oscillation.

const TURN_FRAMES := 80
const TURN_COUNT := 8
const SETTLE_FRAMES := 90
const MIN_TURN_SIGN_CHANGES := 5
const MIN_GROUNDED_RATIO := 0.9
const MAX_DISTANCE_STEP_M := 0.06
const MIN_COMPRESSION_RANGE := 0.05
const MIN_CAMERA_DISTANCE := 3.28
const MAX_CAMERA_DISTANCE := 7.47
const MIN_CAMERA_LEAD_M := 0.10
const MIN_LATERAL_LEAD_M := 0.04
const MIN_LATERAL_LEAD_SIGN_CHANGES := 3

@onready var resort: Node = $Resort

var skier: SkierController
var camera: SkiCameraController
var failures: Array[String] = []
var frame := 0
var grounded_frames := 0
var invalid_frames := 0
var turn_sign_changes := 0
var previous_turn_sign := 0.0
var minimum_distance := INF
var maximum_distance := 0.0
var maximum_distance_step := 0.0
var previous_distance := 0.0
var minimum_compression := INF
var maximum_compression := -INF
var maximum_look_ahead := 0.0
var maximum_lateral_lead := 0.0
var lateral_lead_sign_changes := 0
var previous_lateral_lead_sign := 0.0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	camera = resort.get_node("CameraRig") as SkiCameraController
	if skier == null or camera == null:
		failures.append("Carve stress could not bind the skier and camera")
		_finish()
		return
	await _run_carves()
	_validate()
	_finish()

func _run_carves() -> void:
	await _run_frames(SETTLE_FRAMES)
	var turn_index := 0
	while turn_index < TURN_COUNT:
		var action := "steer_right" if turn_index % 2 == 0 else "steer_left"
		Input.action_press(action, 0.9)
		await _run_frames(TURN_FRAMES)
		Input.action_release(action)
		turn_index += 1
	await _run_frames(30)

func _run_frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame
		frame += 1
		if frame <= SETTLE_FRAMES:
			continue
		var snapshot := camera.debug_snapshot()
		var grounded := skier.state == SkierController.State.GROUND or skier.state == SkierController.State.GRIND
		if grounded:
			grounded_frames += 1
		var recovery_active := bool(snapshot.get("composition_recovery_active", false))
		if grounded and not recovery_active and not bool(snapshot.get("composition_valid", true)):
			invalid_frames += 1
		var distance := float(snapshot.get("target_distance", 0.0))
		if distance > 1.0:
			minimum_distance = minf(minimum_distance, distance)
			maximum_distance = maxf(maximum_distance, distance)
			if previous_distance > 1.0:
				maximum_distance_step = maxf(maximum_distance_step, absf(distance - previous_distance))
			previous_distance = distance
		var debug := skier.animation_controller.debug_snapshot() if skier.animation_controller != null else {}
		var compression := float(debug.get("left_leg_compression", 0.0))
		minimum_compression = minf(minimum_compression, compression)
		maximum_compression = maxf(maximum_compression, compression)
		var look_ahead: Vector3 = snapshot.get("carve_look_ahead_offset", Vector3.ZERO)
		maximum_look_ahead = maxf(maximum_look_ahead, look_ahead.length())
		var normal := skier.contact.average_normal.normalized() if skier.contact.average_normal.length_squared() > 0.01 else Vector3.UP
		var travel := skier.velocity.slide(normal)
		if travel.length_squared() > 0.25:
			var lateral := travel.normalized().cross(normal)
			if lateral.length_squared() > 0.01:
				var lateral_amount := look_ahead.dot(lateral.normalized())
				maximum_lateral_lead = maxf(maximum_lateral_lead, absf(lateral_amount))
				var lead_sign := signf(lateral_amount) if absf(lateral_amount) >= MIN_LATERAL_LEAD_M else 0.0
				if lead_sign != 0.0 and previous_lateral_lead_sign != 0.0 and lead_sign != previous_lateral_lead_sign:
					lateral_lead_sign_changes += 1
				if lead_sign != 0.0:
					previous_lateral_lead_sign = lead_sign
		var turn_sign := signf(skier.edge_amount) if absf(skier.edge_amount) > 0.08 else 0.0
		if turn_sign != 0.0 and previous_turn_sign != 0.0 and turn_sign != previous_turn_sign:
			turn_sign_changes += 1
		if turn_sign != 0.0:
			previous_turn_sign = turn_sign

func _validate() -> void:
	var sampled := maxi(frame - SETTLE_FRAMES, 1)
	var grounded_ratio := float(grounded_frames) / float(sampled)
	if turn_sign_changes < MIN_TURN_SIGN_CHANGES:
		failures.append("Linked carve stress only produced %d edge sign changes" % turn_sign_changes)
	if grounded_ratio < MIN_GROUNDED_RATIO:
		failures.append("High-speed carve stress was grounded for only %.2f of samples" % grounded_ratio)
	if invalid_frames > 0:
		failures.append("Carve stress produced %d grounded hard-composition-invalid frames" % invalid_frames)
	if minimum_distance < MIN_CAMERA_DISTANCE or maximum_distance > MAX_CAMERA_DISTANCE:
		failures.append("Carve stress camera distance escaped its band: (%.2f, %.2f)" % [minimum_distance, maximum_distance])
	if maximum_distance_step > MAX_DISTANCE_STEP_M:
		failures.append("Carve stress distance stepped %.3f m in one frame" % maximum_distance_step)
	var compression_range := maximum_compression - minimum_compression
	if compression_range < MIN_COMPRESSION_RANGE:
		failures.append("Carve stress did not load the stance (range %.3f)" % compression_range)
	if minimum_compression < -1.0 or maximum_compression > 2.0:
		failures.append("Carve stress compression left its sane range: (%.2f, %.2f)" % [minimum_compression, maximum_compression])
	if maximum_look_ahead < MIN_CAMERA_LEAD_M:
		failures.append("Integrated carve camera lead stayed at %.3f m (need at least %.2f m)" % [maximum_look_ahead, MIN_CAMERA_LEAD_M])
	if maximum_lateral_lead < MIN_LATERAL_LEAD_M:
		failures.append("Integrated carve lateral lead stayed at %.3f m (need at least %.2f m)" % [maximum_lateral_lead, MIN_LATERAL_LEAD_M])
	if lateral_lead_sign_changes < MIN_LATERAL_LEAD_SIGN_CHANGES:
		failures.append("Camera lateral lead changed side only %d times (need at least %d)" % [lateral_lead_sign_changes, MIN_LATERAL_LEAD_SIGN_CHANGES])
	print("RELEASE_CARVE_SAMPLE turns=%d sign_changes=%d grounded=%.2f invalid=%d distance=(%.2f,%.2f) max_step=%.3f compression=(%.2f,%.2f) look_ahead=%.2f lateral_lead=%.2f lead_changes=%d" % [
		TURN_COUNT, turn_sign_changes, grounded_ratio, invalid_frames, minimum_distance, maximum_distance, maximum_distance_step, minimum_compression, maximum_compression, maximum_look_ahead, maximum_lateral_lead, lateral_lead_sign_changes
	])

func _finish() -> void:
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("RELEASE_CARVE_STRESS_PASS: sustained linked carves kept camera framing, validity, readable stance loading, and mirrored turn lead")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("RELEASE_CARVE_STRESS_FAIL: " + failure)
	get_tree().quit(1)
