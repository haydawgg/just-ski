extends Node

const ParkLayout := preload("res://world/park_features/park_layout.gd")

var frame_count := 0
@onready var resort: Node = $Resort

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count < 720:
		return
	var skier := resort.get_node_or_null("Skier") as SkierController
	if skier == null:
		push_error("SMOKE_FAIL: Skier was not created")
		get_tree().quit(1)
		return
	var data := skier.telemetry()
	print("SMOKE_TELEMETRY position=", skier.global_position, " speed_mps=", data.speed_mps, " state=", data.state, " contacts=", data.contact_confidence)
	if skier.global_position.z >= ParkLayout.spawn_position().z - 4.0:
		push_error("SMOKE_FAIL: Skier did not travel downhill")
		AudioManager.shutdown_audio()
		get_tree().quit(2)
		return
	if float(data.speed_mps) < 1.0:
		push_error("SMOKE_FAIL: Skier did not gain speed")
		AudioManager.shutdown_audio()
		get_tree().quit(3)
		return
	print("SMOKE_PASS: resort boots, skier contacts terrain, and slope gravity produces motion")
	AudioManager.shutdown_audio()
	get_tree().quit(0)
