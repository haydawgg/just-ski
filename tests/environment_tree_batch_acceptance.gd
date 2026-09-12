extends Node

## Phase 11 tree contract: structural conifer families are batched into
## deterministic, spatially localized MultiMesh chunks so visibility/LOD is
## evaluated on course-length AABBs instead of one whole-course batch.

const RESORT_SCENE := preload("res://world/resort.tscn")
const MAX_COMPONENT_BATCHES := 72
const MAX_CHUNK_SPAN_M := 140.0
const MIN_CHUNK_COUNT := 3
const EXPECTED_FAMILIES := 4

var failures: Array[String] = []

func _ready() -> void:
	var resort := RESORT_SCENE.instantiate() as Node3D
	add_child(resort)
	await get_tree().process_frame
	var batches := get_tree().get_nodes_in_group("park_tree_batches")
	if batches.size() != 1:
		failures.append("Resort did not create exactly one tree render batch root")
	else:
		var batch := batches[0] as Node3D
		var render_nodes := batch.find_children("*", "MultiMeshInstance3D", true, false)
		if render_nodes.is_empty() or render_nodes.size() > MAX_COMPONENT_BATCHES:
			failures.append("Tree batch did not bound its render submissions to %d chunk components" % MAX_COMPONENT_BATCHES)
		var families_seen: Dictionary = {}
		var chunks_seen: Dictionary = {}
		var near_placements := 0
		for node: Node in render_nodes:
			var render := node as MultiMeshInstance3D
			if render == null or render.multimesh == null or render.multimesh.instance_count < 1:
				failures.append("A tree component batch has no instances")
				continue
			var family := int(node.get_meta("tree_family", -1))
			var chunk := int(node.get_meta("tree_chunk", -1))
			var part := str(node.get_meta("tree_part", ""))
			var lod_band := str(node.get_meta("tree_lod", ""))
			families_seen[family] = true
			chunks_seen[chunk] = true
			if lod_band == "near" and part == "trunk":
				near_placements += render.multimesh.instance_count
			var local_bounds := render.multimesh.custom_aabb if render.multimesh.custom_aabb.size != Vector3.ZERO else render.multimesh.get_aabb()
			if local_bounds.size.z > MAX_CHUNK_SPAN_M:
				failures.append("Tree component %s spans %.0f m in z; LOD bounds are not chunk-local" % [node.name, local_bounds.size.z])
		if families_seen.size() < EXPECTED_FAMILIES:
			failures.append("Tree batch exposed %d structural families; expected %d" % [families_seen.size(), EXPECTED_FAMILIES])
		if chunks_seen.size() < MIN_CHUNK_COUNT:
			failures.append("Tree batch did not localize LOD into spatial chunks (%d)" % chunks_seen.size())
		if near_placements != get_tree().get_nodes_in_group("park_trees").size():
			failures.append("Tree chunk components did not contain every deterministic placement (%d of %d)" % [near_placements, get_tree().get_nodes_in_group("park_trees").size()])
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
		if not tree.has_meta("tree_family"):
			failures.append("A batched tree placement is missing its structural family")
	await _test_repeated_commit_does_not_duplicate_placements()
	if failures.is_empty():
		print("ENVIRONMENT_TREE_BATCH_PASS: four deterministic conifer families render through bounded spatial MultiMesh chunks")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("ENVIRONMENT_TREE_BATCH_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _test_repeated_commit_does_not_duplicate_placements() -> void:
	var batch := ParkTreeBatch.new()
	add_child(batch)
	batch.add_tree(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)), 0, 0)
	batch.commit()
	await get_tree().process_frame
	batch.add_tree(Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 85.0)), 1, 1)
	batch.commit()
	await get_tree().process_frame
	var placement_total := 0
	for node: Node in batch.find_children("*", "MultiMeshInstance3D", true, false):
		var render := node as MultiMeshInstance3D
		if render != null and render.multimesh != null and str(node.get_meta("tree_lod", "")) == "near" and str(node.get_meta("tree_part", "")) == "trunk":
			placement_total += render.multimesh.instance_count
	if placement_total != 1:
		failures.append("Repeated tree-batch commit accumulated stale placements (%d)" % placement_total)
	batch.queue_free()
