extends Node

const RESORT_SCENE := preload("res://world/resort.tscn")

var failures: Array[String] = []

func _ready() -> void:
	var resort := RESORT_SCENE.instantiate() as Node3D
	add_child(resort)
	await get_tree().process_frame
	var batches := get_tree().get_nodes_in_group("park_tree_batches")
	if batches.size() != 1:
		failures.append("Resort did not create exactly one tree render batch")
	else:
		var batch := batches[0] as Node3D
		var render_nodes := batch.find_children("*", "MultiMeshInstance3D", true, false)
		if render_nodes.is_empty() or render_nodes.size() > 10:
			failures.append("Tree batch did not bound its render submissions to ten component batches")
		for node: Node in render_nodes:
			var render := node as MultiMeshInstance3D
			if render == null or render.multimesh == null or render.multimesh.instance_count < 24:
				failures.append("A tree component batch did not contain every deterministic tree placement")
	var trees := get_tree().get_nodes_in_group("park_trees")
	if trees.size() < 24:
		failures.append("Batching removed deterministic tree placement roots")
	for tree_node: Node in trees:
		var tree := tree_node as Node3D
		if tree == null or str(tree.get_meta("asset_id", "")) != "park_tree":
			failures.append("A batched tree lost its catalog identity")
			continue
		if tree.find_children("*", "CollisionShape3D", true, false).is_empty():
			failures.append("A batched tree lost its independent collision companion")
	if failures.is_empty():
		print("ENVIRONMENT_TREE_BATCH_PASS: deterministic tree collisions use a bounded MultiMesh render batch")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ENVIRONMENT_TREE_BATCH_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)
