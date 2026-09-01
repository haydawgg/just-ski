extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var frame := 0
var failures: Array[String] = []
var air_seen := false
var flip_seen := false
var flip_state_seen := false
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
		Input.action_press("steer_forward", 1.0)
	elif frame == 205:
		Input.action_release("trick_down")
		Input.action_press("trick_up", 1.0)
	elif frame == 207:
		Input.action_release("trick_up")
		Input.action_release("steer_forward")
	elif frame > 207 and frame < 300:
		if frame == 226:
			Input.action_press("trick_up", 1.0)
		elif frame == 229:
			Input.action_release("trick_up")
		elif frame == 238:
			Input.action_press("trick_down", 1.0)
		elif frame == 241:
			Input.action_release("trick_down")
		if skier.state == SkierController.State.AIR:
			air_seen = true
			if skier.angular_velocity.x > 0.25:
				flip_seen = true
			if skier.trick_rotation_state.active and skier.trick_rotation_state.kind == TrickCommand.Kind.FRONTFLIP:
				flip_state_seen = true
				if skier.trick_rotation_state.primary_progress_radians() > 0.05:
					reference_progress_seen = true
				if skier.trick.accumulated_rotation.distance_to(skier.trick_rotation_state.accumulated_rotation_vector()) < 0.01:
					authoritative_accumulation_seen = true
				maximum_live_compactness = maxf(maximum_live_compactness, skier.trick_rotation_state.compactness)
				minimum_live_compactness = minf(minimum_live_compactness, skier.trick_rotation_state.compactness)
	elif frame == 310:
		_release_inputs()
		if not air_seen or not flip_seen:
			failures.append("Pressure-modified preload did not create a live frontflip takeoff")
		if not flip_state_seen or not reference_progress_seen:
			failures.append("Live frontflip did not use takeoff-reference rotation state")
		if not authoritative_accumulation_seen:
			failures.append("Live frontflip accumulation diverged from authoritative rotation state")
		if maximum_live_compactness <= 0.55 or minimum_live_compactness >= 0.45:
			failures.append("Held frontflip continuation/check input did not compact and open the live body model (max %.3f min %.3f)" % [maximum_live_compactness, minimum_live_compactness])
		_finish()

func _release_inputs() -> void:
	for action: StringName in [&"trick_down", &"trick_up", &"trick_left", &"trick_right", &"steer_forward", &"steer_back"]:
		Input.action_release(action)

func _finish() -> void:
	_release_inputs()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("FLICK_FLIP_GAMEPLAY_PASS: preloaded live flip uses reference rotation and continuous compact/open management")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("FLICK_FLIP_GAMEPLAY_FAIL: " + failure)
		get_tree().quit(1)
