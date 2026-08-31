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
		if skier.state == SkierController.State.AIR:
			air_seen = true
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
		_finish()

func _release_inputs() -> void:
	for action: StringName in [&"trick_down", &"trick_left", &"trick_right", &"trick_up", &"grab_left", &"grab_right"]:
		Input.action_release(action)

func _finish() -> void:
	_release_inputs()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("FLICK_GAMEPLAY_PASS: live preload release builds rotation and neutral-air spin initiation is rejected")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLICK_GAMEPLAY_FAIL: " + failure)
		get_tree().quit(1)
