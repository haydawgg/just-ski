extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var frame := 0
var failures: Array[String] = []
var air_seen := false
var spin_seen := false

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 180:
		Input.action_press("trick_down", 1.0)
	elif frame == 205:
		Input.action_release("trick_down")
		Input.action_press("trick_left", 1.0)
	elif frame == 207:
		Input.action_release("trick_left")
	elif frame > 207 and frame < 300:
		if skier.state == SkierController.State.AIR:
			air_seen = true
		if skier.angular_velocity.y < -0.25:
			spin_seen = true
	elif frame == 310:
		if not air_seen:
			failures.append("Right-stick preload/flick did not pop the live skier")
		if not spin_seen:
			failures.append("Directional takeoff did not apply its spin impulse")
		_finish()

func _finish() -> void:
	for action: StringName in [&"trick_down", &"trick_left", &"trick_right", &"trick_up", &"grab_left", &"grab_right"]:
		Input.action_release(action)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("FLICK_GAMEPLAY_PASS: live skier popped and spun from a right-stick gesture")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLICK_GAMEPLAY_FAIL: " + failure)
		get_tree().quit(1)
