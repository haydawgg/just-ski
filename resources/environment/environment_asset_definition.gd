class_name EnvironmentAssetDefinition
extends Resource

## Data contract for a production environment asset.
##
## The generated graybox can use this contract without needing an imported
## scene yet.  Once a visual_scene is assigned, the same metadata validates
## scale, collision policy, readability, and LOD expectations at build time.

enum AssetClass { SOLID, GRIND_ONLY, GUIDE, BOUNDARY, DECORATION }

@export var asset_id: String = ""
@export var visual_scene: PackedScene
@export var collision_scene: PackedScene
@export var parametric_feature := false
@export var nominal_size_m: Vector3 = Vector3.ONE
@export_range(0.01, 0.5, 0.01) var scale_tolerance: float = 0.10
@export var asset_class: AssetClass = AssetClass.SOLID
@export var readability_category: String = "feature"
@export var source_license: String = "project-authored"
@export var lod_distances_m: Vector3 = Vector3(30.0, 90.0, 180.0)

func has_production_scene() -> bool:
	return visual_scene != null

func has_collision_scene() -> bool:
	return collision_scene != null

func validate() -> Array[String]:
	var failures: Array[String] = []
	if asset_id.strip_edges().is_empty():
		failures.append("asset_id is empty")
	if nominal_size_m.x <= 0.0 or nominal_size_m.y <= 0.0 or nominal_size_m.z <= 0.0:
		failures.append("nominal_size_m must be positive")
	if scale_tolerance <= 0.0 or scale_tolerance >= 0.5:
		failures.append("scale_tolerance must be between 0 and 0.5")
	if lod_distances_m.x <= 0.0 or lod_distances_m.y <= lod_distances_m.x or lod_distances_m.z <= lod_distances_m.y:
		failures.append("lod_distances_m must be strictly increasing")
	if source_license.strip_edges().is_empty():
		failures.append("source_license is empty")
	if asset_class == AssetClass.GUIDE and collision_scene != null:
		failures.append("GUIDE asset must not declare collision_scene")
	if asset_class == AssetClass.SOLID and visual_scene != null and collision_scene == null and not parametric_feature:
		failures.append("SOLID asset has a visual scene but no collision scene")
	return failures

func validate_instance(instance: Node3D) -> Array[String]:
	"""Audit an instantiated authored scene against its catalog contract."""
	var failures: Array[String] = []
	if instance == null:
		failures.append("scene instance is null")
		return failures
	var bounds := AABB()
	var has_bounds := false
	var mesh_nodes: Array[Node] = []
	if instance is MeshInstance3D:
		mesh_nodes.append(instance)
		mesh_nodes.append_array(instance.find_children("*", "MeshInstance3D", true, false))
	else:
		mesh_nodes = instance.find_children("*", "MeshInstance3D", true, false)
	for node: Node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.mesh.get_aabb()
		for corner: Vector3 in _aabb_corners(mesh_bounds):
			# Validate in the asset root's authored coordinate system. Resort
			# placement, slope rotation, and an intentional per-instance scale
			# override must not change the source scene's meter dimensions.
			var local_point := instance.to_local(mesh_instance.to_global(corner))
			if not has_bounds:
				bounds = AABB(local_point, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(local_point)
	if not has_bounds:
		failures.append("scene has no MeshInstance3D bounds to validate")
		return failures
	var actual_size := bounds.size
	var expected_size := nominal_size_m
	var actual_axes := [actual_size.x, actual_size.y, actual_size.z]
	var expected_axes := [expected_size.x, expected_size.y, expected_size.z]
	actual_axes.sort()
	expected_axes.sort()
	for axis: int in 3:
		var expected := maxf(float(expected_axes[axis]), 0.001)
		if absf(float(actual_axes[axis]) - expected) / expected > scale_tolerance:
			failures.append("visible dimension %.3f m differs from nominal %.3f m by more than %.0f%%" % [actual_axes[axis], expected, scale_tolerance * 100.0])
	if absf(bounds.position.y) > 0.05:
		var direction := "below" if bounds.position.y < 0.0 else "above"
		failures.append("scene origin is %s the snow-contact point by %.3f m" % [direction, absf(bounds.position.y)])
	return failures

func _aabb_corners(value: AABB) -> Array[Vector3]:
	var p := value.position
	var s := value.size
	return [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]
