extends Node

const SKIER_VISUAL_SCENE := preload("res://player/animation/skier_visual.tscn")
const DIMENSION_TOLERANCE := 0.0005
const SCALE_TOLERANCE := 0.0005

var failures: Array[String] = []

func _ready() -> void:
	var controller := SKIER_VISUAL_SCENE.instantiate() as SkierAnimationController
	add_child(controller)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_GROUND
	frame.grounded = true
	controller.apply_frame(frame, 1.0 / 60.0)
	await get_tree().process_frame
	_measure_production_visual(controller)
	if failures.is_empty():
		print("CHARACTER_EQUIPMENT_SCALE_PASS: production body/equipment dimensions, mounts, uniform transforms, and single-rig visibility passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("CHARACTER_EQUIPMENT_SCALE_FAIL: " + failure)
		get_tree().quit(1)

func _measure_production_visual(controller: SkierAnimationController) -> void:
	var adapter := controller.rig_adapter as SkeletonSkierRig
	_check(adapter != null, "Production visual did not select SkeletonSkierRig")
	if adapter == null:
		return
	var body_bounds := _combined_skinned_body_bounds(adapter.body_root)
	var left_ski := controller.find_child("LeftSkiMesh", true, false) as MeshInstance3D
	var right_ski := controller.find_child("RightSkiMesh", true, false) as MeshInstance3D
	var left_boot := controller.find_child("LeftBootMesh", true, false) as MeshInstance3D
	var right_boot := controller.find_child("RightBootMesh", true, false) as MeshInstance3D
	var left_pole := controller.find_child("LeftPoleMesh", true, false) as MeshInstance3D
	var right_pole := controller.find_child("RightPoleMesh", true, false) as MeshInstance3D
	for required: MeshInstance3D in [left_ski, right_ski, left_boot, right_boot, left_pole, right_pole]:
		_check(required != null, "Required production equipment mesh is missing")
	if left_ski == null or right_ski == null or left_boot == null or right_boot == null or left_pole == null or right_pole == null:
		return
	var left_dimensions := _mesh_axis_dimensions(left_ski)
	var right_dimensions := _mesh_axis_dimensions(right_ski)
	var skier_height := body_bounds.size.y
	var left_ski_length := left_dimensions.z
	var left_ski_width := left_dimensions.x
	var right_ski_length := right_dimensions.z
	var right_ski_width := right_dimensions.x
	var left_pole_length := _mesh_axis_dimensions(left_pole).y
	var right_pole_length := _mesh_axis_dimensions(right_pole).y
	var left_pole_diameter := maxf(_mesh_axis_dimensions(left_pole).x, _mesh_axis_dimensions(left_pole).z)
	var right_pole_diameter := maxf(_mesh_axis_dimensions(right_pole).x, _mesh_axis_dimensions(right_pole).z)
	var left_boot_gap := _boot_ski_gap(left_boot, left_ski)
	var right_boot_gap := _boot_ski_gap(right_boot, right_ski)
	var ski_orientation_error := _mirrored_basis_error(left_ski.global_basis, right_ski.global_basis)
	print("CHARACTER_SCALE_MEASURE skier_height=%.4f" % skier_height)
	print("CHARACTER_SCALE_MEASURE left_ski_length=%.4f left_ski_width=%.4f left_ski_thickness=%.4f" % [left_ski_length, left_ski_width, left_dimensions.y])
	print("CHARACTER_SCALE_MEASURE right_ski_length=%.4f right_ski_width=%.4f right_ski_thickness=%.4f" % [right_ski_length, right_ski_width, right_dimensions.y])
	print("CHARACTER_SCALE_MEASURE left_pole_length=%.4f right_pole_length=%.4f pole_diameter=%.4f ski_height_ratio=%.4f" % [left_pole_length, right_pole_length, left_pole_diameter, left_ski_length / maxf(skier_height, 0.001)])
	print("CHARACTER_SCALE_MEASURE left_boot_ski_gap=%.4f right_boot_ski_gap=%.4f" % [left_boot_gap, right_boot_gap])
	print("CHARACTER_SCALE_MEASURE left_right_ski_orientation_error=%.7f" % ski_orientation_error)
	_check(skier_height >= 1.62 and skier_height <= 1.98, "Adult skier visual height %.3fm is outside the accepted 1.62-1.98m range" % skier_height)
	_check(left_ski_length >= 1.55 and left_ski_length <= 1.95, "Left ski length %.3fm is outside the accepted adult range" % left_ski_length)
	_check(right_ski_length >= 1.55 and right_ski_length <= 1.95, "Right ski length %.3fm is outside the accepted adult range" % right_ski_length)
	_check(absf(left_ski_length - right_ski_length) <= DIMENSION_TOLERANCE, "Left/right ski lengths differ by %.6fm" % absf(left_ski_length - right_ski_length))
	_check(absf(left_ski_width - right_ski_width) <= DIMENSION_TOLERANCE, "Left/right ski widths differ by %.6fm" % absf(left_ski_width - right_ski_width))
	_check(absf(left_dimensions.y - right_dimensions.y) <= DIMENSION_TOLERANCE, "Left/right ski thicknesses differ by %.6fm" % absf(left_dimensions.y - right_dimensions.y))
	_check(ski_orientation_error <= 0.0005, "Left/right ski neutral orientations disagree by %.7f" % ski_orientation_error)
	_check(left_ski_width >= 0.085 and left_ski_width <= 0.13, "Ski width %.3fm is outside the accepted adult range" % left_ski_width)
	_check(left_dimensions.y >= 0.012 and left_dimensions.y <= 0.035, "Ski thickness %.3fm is outside the accepted visual range" % left_dimensions.y)
	var ski_height_ratio := left_ski_length / maxf(skier_height, 0.001)
	_check(ski_height_ratio >= 0.84 and ski_height_ratio <= 1.08, "Ski/body ratio %.3f is not believable for the adult skier" % ski_height_ratio)
	_check(absf(left_pole_length - right_pole_length) <= DIMENSION_TOLERANCE, "Left/right pole lengths differ")
	_check(absf(left_pole_diameter - right_pole_diameter) <= DIMENSION_TOLERANCE, "Left/right pole shaft diameters differ")
	_check(left_pole_length / maxf(skier_height, 0.001) >= 0.55 and left_pole_length / maxf(skier_height, 0.001) <= 0.78, "Pole/body proportion is outside the accepted range")
	_check(left_pole_diameter >= 0.018 and left_pole_diameter <= 0.04, "Pole shaft diameter %.3fm is visually disproportionate" % left_pole_diameter)
	_check(left_boot_gap <= 0.065, "Left boot is not seated on the ski (gap %.3fm)" % left_boot_gap)
	_check(right_boot_gap <= 0.065, "Right boot is not seated on the ski (gap %.3fm)" % right_boot_gap)
	_check(controller.find_child("PrimitiveRigAdapter", true, false) == null, "Old primitive rig remains instantiated beside the skeleton rig")
	var outside_mesh_count := 0
	for node: Node in controller.find_children("*", "MeshInstance3D", true, false):
		if not adapter.is_ancestor_of(node):
			outside_mesh_count += 1
	_check(outside_mesh_count == 0, "%d rendered debug/reference meshes remain outside the selected rig adapter" % outside_mesh_count)
	var maximum_scale_spread := 0.0
	for node: Node in adapter.find_children("*", "Node3D", true, false):
		var spatial := node as Node3D
		var local_scale := _basis_axis_lengths(spatial.basis)
		var spread := maxf(local_scale.x, maxf(local_scale.y, local_scale.z)) - minf(local_scale.x, minf(local_scale.y, local_scale.z))
		maximum_scale_spread = maxf(maximum_scale_spread, spread)
		_check(spread <= SCALE_TOLERANCE, "Non-uniform local scale %s on %s" % [local_scale, str(adapter.get_path_to(spatial))])
	print("CHARACTER_SCALE_MEASURE maximum_nonuniform_scale_spread=%.7f outside_rig_meshes=%d" % [maximum_scale_spread, outside_mesh_count])

func _mesh_axis_dimensions(instance: MeshInstance3D) -> Vector3:
	var local_size := instance.get_aabb().size
	return Vector3(
		local_size.x * instance.global_basis.x.length(),
		local_size.y * instance.global_basis.y.length(),
		local_size.z * instance.global_basis.z.length()
	)

func _combined_skinned_body_bounds(root: Node) -> AABB:
	var bounds := AABB()
	var initialized := false
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.skin == null and instance.skeleton.is_empty():
			continue
		var world_bounds := _transformed_aabb(instance.get_aabb(), instance.global_transform)
		bounds = world_bounds if not initialized else bounds.merge(world_bounds)
		initialized = true
	return bounds

func _transformed_aabb(local_bounds: AABB, transform: Transform3D) -> AABB:
	var result := AABB()
	var initialized := false
	for x: int in [0, 1]:
		for y: int in [0, 1]:
			for z: int in [0, 1]:
				var local_point := local_bounds.position + Vector3(local_bounds.size.x * x, local_bounds.size.y * y, local_bounds.size.z * z)
				var world_point := transform * local_point
				if not initialized:
					result = AABB(world_point, Vector3.ZERO)
					initialized = true
				else:
					result = result.expand(world_point)
	return result

func _boot_ski_gap(boot: MeshInstance3D, ski: MeshInstance3D) -> float:
	var boot_bounds := _transformed_aabb(boot.get_aabb(), boot.global_transform)
	var ski_bounds := _transformed_aabb(ski.get_aabb(), ski.global_transform)
	return absf(boot_bounds.position.y - ski_bounds.end.y)

func _basis_axis_lengths(value: Basis) -> Vector3:
	return Vector3(value.x.length(), value.y.length(), value.z.length())

func _mirrored_basis_error(left: Basis, right: Basis) -> float:
	var left_orthonormal := left.orthonormalized()
	var right_orthonormal := right.orthonormalized()
	return maxf(
		1.0 - absf(left_orthonormal.x.dot(right_orthonormal.x)),
		maxf(
			1.0 - absf(left_orthonormal.y.dot(right_orthonormal.y)),
			1.0 - absf(left_orthonormal.z.dot(right_orthonormal.z))
		)
	)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
