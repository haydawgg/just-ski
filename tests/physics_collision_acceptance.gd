extends Node

@onready var resort: Node = $Resort
var skier: SkierController
var frame := 0
var failures: Array[String] = []
var grounded_frames := 0
var air_frames := 0
var kicker_seen := false
var kicker_speed := 0.0
var grind_speed := 0.0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	_test_tree_block.call_deferred()

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame >= 180 and frame <= 360:
		if skier.state == SkierController.State.GROUND:
			grounded_frames += 1
		elif skier.state == SkierController.State.AIR:
			air_frames += 1
	if frame == 360:
		var total := grounded_frames + air_frames
		if total == 0 or float(grounded_frames) / float(total) < 0.7:
			failures.append("Main-face contact was not stably grounded")
		_place_on_kicker_line()
	elif frame > 360 and frame < 520:
		if not kicker_seen and skier.global_position.z <= 46.0 and skier.global_position.z >= 38.0:
			kicker_seen = true
			kicker_speed = skier.velocity.length()
			if skier.state == SkierController.State.BAIL:
				failures.append("Kicker ride entered Bail")
			if kicker_speed < 2.5:
				failures.append("Kicker ride collapsed speed")
	elif frame == 520:
		if not kicker_seen:
			failures.append("Skier never reached the first kicker")
		_place_on_rail_approach()
	elif frame == 590:
		if skier.state != SkierController.State.GRIND:
			failures.append("Rail approach did not capture grind")
		else:
			grind_speed = skier.rail_speed
			if grind_speed < 3.0:
				failures.append("Rail capture collapsed speed")
		_finish()

func _place_on_kicker_line() -> void:
	skier.global_position = Vector3(-11.0, 18.4, 52.0)
	skier.velocity = Vector3(0.0, -1.0, -9.0)
	skier.global_basis = Basis.looking_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.state = SkierController.State.AIR
	skier.air_time = 0.2

func _place_on_rail_approach() -> void:
	var rail := resort.get_node("DownRail") as GrindRail3D
	var offset := rail.path_length * 0.25
	var tangent := rail.tangent_at(offset)
	skier.global_position = rail.sample_world(offset) + Vector3.UP * 0.55
	skier.velocity = tangent * 10.0
	skier.global_basis = Basis.looking_at(tangent, Vector3.UP)
	skier.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	skier.state = SkierController.State.AIR
	skier.air_time = 0.2
	skier.active_rail = null
	skier.contact.grounded = false
	skier.contact.last_normal = Vector3.UP

func _test_tree_block() -> void:
	var trees := get_tree().get_nodes_in_group("park_trees")
	if trees.is_empty():
		failures.append("Park trees were not spawned as obstacles")
		return
	var tree := trees[0] as Node3D
	var origin := tree.global_position + Vector3(2.0, 1.7, 0.0)
	var target := tree.global_position + Vector3(0.0, 1.7, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, target, 4)
	var hit := skier.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		failures.append("Tree trunk was not solid")

func _finish() -> void:
	print(
		"COLLISION_TELEMETRY grounded=", grounded_frames,
		" air=", air_frames,
		" kicker_speed=", kicker_speed,
		" grind_speed=", grind_speed,
		" state=", SkierController.State.keys()[skier.state]
	)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("COLLISION_PASS: kicker ride, rail capture, contact stability, and tree block checks passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("COLLISION_FAIL: " + failure)
		get_tree().quit(1)
