extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var frame := 0
var failures: Array[String] = []
var air_seen := false
var spin_seen := false
var first_release_speed := -1.0
var later_release_speed := -1.0
var neutral_air_rotation_seen := false
var neutral_air_flip_seen := false
var rotation_state_seen := false
var reference_progress_seen := false
var authoritative_accumulation_seen := false
var maximum_live_compactness := 0.5
var minimum_live_compactness := 0.5

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 180:
		Input.action_press("trick_down", 1.0)
	elif frame == 205:
		Input.action_release("trick_down")
		Input.action_press("trick_left", 1.0)
	elif frame == 206:
		if skier.state == SkierController.State.AIR:
			first_release_speed = absf(skier.angular_velocity.y)
	elif frame == 207:
		Input.action_release("trick_left")
	elif frame > 207 and frame < 300:
		if frame == 226:
			Input.action_press("trick_left", 1.0)
		elif frame == 229:
			Input.action_release("trick_left")
		elif frame == 238:
			Input.action_press("trick_right", 1.0)
		elif frame == 241:
			Input.action_release("trick_right")
		if skier.state == SkierController.State.AIR:
			air_seen = true
			if skier.trick_rotation_state.active:
				rotation_state_seen = true
				if absf(skier.trick_rotation_state.primary_progress_radians()) > 0.05:
					reference_progress_seen = true
				if skier.trick.accumulated_rotation.distance_to(skier.trick_rotation_state.accumulated_rotation_vector()) < 0.01:
					authoritative_accumulation_seen = true
				maximum_live_compactness = maxf(maximum_live_compactness, skier.trick_rotation_state.compactness)
				minimum_live_compactness = minf(minimum_live_compactness, skier.trick_rotation_state.compactness)
		if skier.angular_velocity.y < -0.25:
			spin_seen = true
		if frame == 214:
			later_release_speed = absf(skier.angular_velocity.y)
	elif frame == 310:
		if not air_seen:
			failures.append("Right-stick preload/flick did not pop the live skier")
		if not spin_seen:
			failures.append("Directional takeoff did not apply its spin impulse")
		if first_release_speed < 0.0 or later_release_speed < 0.0:
			failures.append("Live skier did not expose both early and later takeoff-release samples")
		elif later_release_speed <= first_release_speed + 0.25:
			failures.append("Preloaded rotation did not build across the takeoff release window")
		if not rotation_state_seen or not reference_progress_seen:
			failures.append("Live skier did not activate and advance takeoff-reference rotation state")
		if not authoritative_accumulation_seen:
			failures.append("Live trick accumulation did not follow the authoritative rotation state")
		if maximum_live_compactness <= 0.55 or minimum_live_compactness >= 0.45:
			failures.append("Held continuation/check input did not visibly compact and open the live rotation model (max %.3f min %.3f)" % [maximum_live_compactness, minimum_live_compactness])
		_release_inputs()
		var airborne_transform := skier.global_transform
		airborne_transform.origin += Vector3.UP * 8.0
		skier.reset_for_benchmark(airborne_transform, Vector3.ZERO)
	elif frame == 313:
		# The reset has already spent centered frames in AIR, so this is a fresh
		# neutral-air trick flick rather than a held input carried through takeoff.
		Input.action_press("trick_left", 1.0)
	elif frame > 313 and frame <= 318:
		if absf(skier.angular_velocity.y) > 0.10:
			neutral_air_rotation_seen = true
	elif frame == 319:
		Input.action_release("trick_left")
	elif frame == 330:
		if neutral_air_rotation_seen:
			failures.append("Fresh neutral-air spin flick created major live skier rotation without preload")
		Input.action_press("trick_up", 1.0)
	elif frame > 330 and frame <= 336:
		if absf(skier.angular_velocity.x) > 0.10:
			neutral_air_flip_seen = true
	elif frame == 337:
		Input.action_release("trick_up")
	elif frame == 345:
		if neutral_air_flip_seen:
			failures.append("Fresh neutral-air flip flick created major live skier rotation without preload")
		_finish()

func _release_inputs() -> void:
	for action: StringName in [&"trick_down", &"trick_left", &"trick_right", &"trick_up", &"grab_left", &"grab_right"]:
		Input.action_release(action)

func _finish() -> void:
	_release_inputs()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("FLICK_GAMEPLAY_PASS: live preload release builds rotation and neutral-air spin/flip initiation is rejected")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLICK_GAMEPLAY_FAIL: " + failure)
		get_tree().quit(1)
