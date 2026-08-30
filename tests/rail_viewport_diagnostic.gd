extends Node

# Geometry diagnostic for rail segmentation: verifies continuous smooth visual mesh.

var diag_rails: Array[GrindRail3D] = []
var results: Array[Dictionary] = []

func _ready() -> void:
	await get_tree().process_frame
	_create_rails()
	await get_tree().process_frame
	await get_tree().process_frame
	_evaluate()

func _create_rails() -> void:
	var straight := _build_test_rail(GrindRail3D.RailType.BOX, [Vector3(0,0.22,0), Vector3(0,0.22,-12)], "BOX")
	var curved := _build_test_rail(GrindRail3D.RailType.RAIL, [Vector3(0,0.16,0), Vector3(2,0.16,-4), Vector3(-1,0.16,-8), Vector3(0,0.16,-12)], "CURVE")
	diag_rails.append(straight)
	diag_rails.append(curved)

func _build_test_rail(type: int, points: Array, label: String) -> GrindRail3D:
	var rail := GrindRail3D.new()
	rail.name = "Diag%sRail" % label
	rail.set_meta("diag_label", label)
	rail.rail_type = type
	rail.path = Curve3D.new()
	for p: Vector3 in points:
		rail.path.add_point(p)
	add_child(rail)
	return rail

func _evaluate() -> void:
	print("RAIL_VIEWPORT_DIAG_START")
	for rail in diag_rails:
		var label: String = str(rail.get_meta("diag_label"))
		var visual := rail.get_node_or_null("ContinuousRailVisual") as MeshInstance3D
		if visual == null or visual.mesh == null:
			results.append({"label": label, "pass": false, "reason": "no visual"})
			continue
		var mesh := visual.mesh as ArrayMesh
		if mesh.get_surface_count() != 1:
			results.append({"label": label, "pass": false, "reason": "not single surface"})
			continue
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tri_count := verts.size() / 3
		var max_dihedral := 0.0
		for i in range(0, min(verts.size() - 6, 120), 3):
			var n1: Vector3 = normals[i]
			var n2: Vector3 = normals[i + 3]
			if n1.length_squared() < 0.01 or n2.length_squared() < 0.01:
				continue
			if verts[i].distance_to(verts[i + 3]) < 0.35:
				var angle := rad_to_deg(n1.angle_to(n2))
				max_dihedral = max(max_dihedral, angle)
		var collision_bodies := rail.find_children("*", "StaticBody3D", true, false).size()
		print("RAIL_%s_DIAG: tris %d max_dihedral %.2f collision %d" % [label, tri_count, max_dihedral, collision_bodies])
		var threshold := 50.0 if label == "BOX" else 35.0
		var ok := max_dihedral < threshold
		results.append({"label": label, "pass": ok, "max_dihedral": max_dihedral, "reason": "" if ok else "dihedral %.1f >%.0f" % [max_dihedral, threshold]})
	var reasons: Array[String] = []
	for r in results:
		if not bool(r.pass):
			reasons.append("%s %s" % [r.label, r.reason])
	if reasons.is_empty():
		print("RAIL_VIEWPORT_PASS: continuous smooth rails")
		get_tree().quit(0)
	else:
		for reason in reasons:
			push_error("RAIL_VIEWPORT_FAIL: " + reason)
		get_tree().quit(1)
