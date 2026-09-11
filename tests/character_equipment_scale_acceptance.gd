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
	await _measure_primitive_fallback()
	_measure_shared_equipment(controller)
	await _measure_bare_driver_details()
	_check_region_materials()
	if failures.is_empty():
		print("CHARACTER_EQUIPMENT_SCALE_PASS: production body/equipment dimensions, mounts, uniform transforms, single-rig visibility, and fallback parity passed")
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
	_report_production_torso_surface(adapter)
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
	_check(left_pole_diameter >= 0.012 and left_pole_diameter <= 0.022, "Pole shaft diameter %.3fm is visually disproportionate" % left_pole_diameter)
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
	_check_collar_skirt(adapter)

func _check_collar_skirt(adapter: SkeletonSkierRig) -> void:
	# Jacket shell must overlap the collar cut as a skirt: count jacket verts
	# above the cut. Straddling body triangles contribute a small baseline;
	# the skirt adds its full triangle band on top.
	var above := 0
	for node: Node in adapter.body_root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.skin == null and instance.skeleton.is_empty():
			continue
		for surface_index: int in instance.mesh.get_surface_count():
			var override := instance.get_surface_override_material(surface_index) as StandardMaterial3D
			if override == null or override.resource_name != "Outfit_Jacket":
				continue
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				if (instance.transform * v).y > 0.635:
					above += 1
	print("CHARACTER_SCALE_MEASURE collar_skirt_verts=%d" % above)
	# Pre-skirt GLBs carry a ~12-vert baseline from straddling body triangles;
	# the rebuilt skirt adds its full band on top (18 in the current build).
	_check(above > 12,
		"Jacket collar skirt is missing above the 0.62 cut (%d verts)" % above)

func _report_production_torso_surface(adapter: SkeletonSkierRig) -> void:
	# Compare attachments with the posed production mesh, not bind-pose vertices.
	# Pelvis translation and torso articulation move both mesh and attachments.
	# Single mesh traversal: caches torso-band verts once, answers everything.
	var cloud := PackedVector3Array()
	var head_idx := int(adapter.bone_indices[&"head"])
	var head_y := (adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(head_idx)).origin.y
	var face := PackedVector3Array()
	for node: Node in adapter.body_root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.skin == null and instance.skeleton.is_empty():
			continue
		for surface_index: int in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var skin_transforms: Array[Transform3D] = []
			if instance.skin != null:
				for bind: int in instance.skin.get_bind_count():
					var bone := instance.skin.get_bind_bone(bind)
					var bone_name := instance.skin.get_bind_name(bind)
					if not bone_name.is_empty():
						bone = adapter.skeleton.find_bone(bone_name)
					skin_transforms.append(adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / maxi(verts.size(), 1)
			for vertex: int in verts.size():
				var w: Vector3 = instance.global_transform * verts[vertex]
				if not skin_transforms.is_empty() and influences > 0:
					w = Vector3.ZERO
					for influence: int in influences:
						var index := vertex * influences + influence
						w += (skin_transforms[bones[index]] * verts[vertex]) * weights[index]
				if w.y > 1.2 and w.y < 1.62:
					cloud.append(w)
				if absf(w.x) < 0.05 and w.y > head_y - 0.10 and w.y < head_y + 0.16:
					face.append(w)
	print("CHARACTER_SCALE_MEASURE production torso_cloud=%d" % cloud.size())
	for part_name: String in ["JacketBackStripe", "JacketFrontZip", "JacketChestPocket"]:
		var part := adapter.find_child(part_name, true, false) as MeshInstance3D
		if part == null:
			continue
		var box := part.get_aabb()
		var py := part.global_position.y
		var wall_back := -INF
		var wall_front := INF
		for w: Vector3 in cloud:
			# Narrow x-window around the part's own footprint: a wide window
			# compares the pocket against the protruding sternum centerline.
			if absf(w.y - py) > 0.05 or absf(w.x - part.global_position.x) > 0.03:
				continue
			wall_back = maxf(wall_back, w.z)
			wall_front = minf(wall_front, w.z)
		print("CHARACTER_SCALE_MEASURE production %s y=%.4f wall=[%.4f,%.4f] part=[%.4f,%.4f]" % [
			part_name, py, wall_front, wall_back,
			part.global_position.z - box.size.z * 0.5, part.global_position.z + box.size.z * 0.5])
		# Positive gap = inner face embedded behind the skin, negative = hover.
		var gap := 0.0
		if part_name == "JacketBackStripe":
			gap = wall_back - (part.global_position.z - box.size.z * 0.5)
		else:
			gap = (part.global_position.z + box.size.z * 0.5) - wall_front
		_check(gap >= -0.002 and gap <= 0.010,
			"Production %s is outside the torso seating envelope (signed embedding %.1fmm)" % [part_name, gap * 1000.0])
	var pocket := adapter.find_child("JacketChestPocket", true, false) as MeshInstance3D
	if pocket != null:
		var bins := [-0.16, -0.12, -0.08, -0.04, 0.0]
		var fronts := {}
		for b: float in bins:
			fronts[b] = INF
		for w2: Vector3 in cloud:
			if absf(w2.y - pocket.global_position.y) > 0.04:
				continue
			for b2: float in bins:
				if absf(w2.x - b2) < 0.025:
					fronts[b2] = minf(float(fronts[b2]), w2.z)
		var line := "CHARACTER_SCALE_MEASURE production wall_profile y=%.4f" % pocket.global_position.y
		for b3: float in bins:
			line += " x%.2f=%.4f" % [b3, float(fronts[b3])]
		print(line)
	_report_face_profile(adapter, face)

func _report_face_profile(adapter: SkeletonSkierRig, face: PackedVector3Array) -> void:
	# Front-most z per y-bin across the face band + chin location, so a
	# procedural mouth can be seated on the real base-mesh face, not a guess.
	var head_idx := int(adapter.bone_indices[&"head"])
	var head_y := (adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(head_idx)).origin.y
	var bins := {}
	var y := head_y - 0.10
	while y <= head_y + 0.16:
		bins[snappedf(y, 0.01)] = INF
		y += 0.02
	var chin := INF
	for w: Vector3 in face:
		var key := snappedf(w.y, 0.01)
		if bins.has(key):
			bins[key] = minf(float(bins[key]), w.z)
		if w.z < -0.03:
			chin = minf(chin, w.y)
	var line := "CHARACTER_SCALE_MEASURE face_profile head_y=%.4f chin=%.4f" % [head_y, chin]
	var keys := bins.keys()
	keys.sort()
	for k: float in keys:
		line += " %.2f=%.4f" % [k, float(bins[k])]
	print(line)

func _measure_primitive_fallback() -> void:
	# The fallback rig must match production styling: proportioned torso that
	# fits its own pelvis/shoulder shells, readable glove, full sleeve/jacket
	# detail, and outfit-spec materials (not hardcoded values).
	var driver := SkierPoseDriver.new()
	add_child(driver)
	driver.build()
	var rig := PrimitiveSkierRig.new()
	add_child(rig)
	if not rig.configure(driver):
		_check(false, "Primitive fallback rig failed to configure: " + rig.validation_error())
		remove_child(rig)
		rig.free()
		remove_child(driver)
		driver.free()
		return
	await get_tree().process_frame
	var outfit := rig.outfit_profile
	var pelvis := driver.find_child("PelvisMesh", true, false) as MeshInstance3D
	var torso := driver.find_child("TorsoMesh", true, false) as MeshInstance3D
	var shoulders := driver.find_child("ShoulderJacket", true, false) as MeshInstance3D
	var glove := driver.find_child("LeftGlove", true, false) as MeshInstance3D
	var hip_span := driver.joint(&"left_hip").position.distance_to(driver.joint(&"right_hip").position)
	var leg_chain := driver.joint(&"left_knee").position.length() + driver.joint(&"left_boot").position.length()
	var torso_chain := driver.joint(&"spine").position.length() + driver.joint(&"chest").position.length() + driver.joint(&"head").position.length()
	print("CHARACTER_SCALE_MEASURE anthropometry hip_span=%.3f leg_torso_ratio=%.3f" % [hip_span, leg_chain / maxf(torso_chain, 0.001)])
	_check(hip_span >= 0.20 and hip_span <= 0.32,
		"Fallback hip-center span %.3fm is outside a believable adult range" % hip_span)
	_check(leg_chain / maxf(torso_chain, 0.001) >= 0.82 and leg_chain / maxf(torso_chain, 0.001) <= 1.02,
		"Fallback leg/torso chain ratio %.3f is outside the calibrated human range" % (leg_chain / maxf(torso_chain, 0.001)))
	_check(pelvis != null and torso != null and shoulders != null and glove != null,
		"Primitive fallback body shells are missing")
	if pelvis != null and torso != null and shoulders != null and glove != null:
		var pelvis_size := pelvis.get_aabb().size
		var torso_size := torso.get_aabb().size
		var shoulder_size := shoulders.get_aabb().size
		var glove_size := glove.get_aabb().size
		print("CHARACTER_SCALE_MEASURE fallback pelvis=%.3f torso=%.3fx%.3f shoulders=%.3fx%.3f glove=%.3fx%.3f" % [
			pelvis_size.x, torso_size.x, torso_size.z, shoulder_size.x, shoulder_size.z,
			glove_size.x, glove_size.y])
		_check(torso_size.x <= pelvis_size.x + 0.04,
			"Fallback torso (%.3fm) barrels past its pelvis shell (%.3fm)" % [torso_size.x, pelvis_size.x])
		_check(torso_size.z <= shoulder_size.z + 0.06,
			"Fallback torso (%.3fm deep) protrudes past the shoulder shell (%.3fm)" % [torso_size.z, shoulder_size.z])
		_check(shoulder_size.x * 0.5 >= 0.40,
			"Fallback shoulder block (half %.3fm) leaves the ±0.40m arm joints outside" % (shoulder_size.x * 0.5))
		_check(pelvis_size.x * 0.5 >= 0.27,
			"Fallback pelvis shell (half %.3fm) leaves the ±0.27m hip joints outside" % (pelvis_size.x * 0.5))
		_check(glove_size.x <= 0.125,
			"Fallback glove (%.3fm wide) reads as a mitten ball" % glove_size.x)
		_check((glove.material_override as StandardMaterial3D).albedo_color.is_equal_approx(outfit.glove_color),
			"Fallback glove ignores the outfit glove color")
	for part_name: String in ["LeftUpperSleeve", "RightUpperSleeve", "LeftForearmSleeve", "RightForearmSleeve",
			"LeftSleeveCuff", "RightSleeveCuff", "JacketBackStripe", "JacketFrontZip", "JacketChestPocket", "NeckMesh"]:
		_check(driver.find_child(part_name, true, false) is MeshInstance3D,
			"Fallback rig is missing production-parity detail " + part_name)
	var jacket := driver.find_child("TorsoMesh", true, false) as MeshInstance3D
	if jacket != null:
		_check(absf((jacket.material_override as StandardMaterial3D).metallic_specular - outfit.cloth_specular) <= 0.01,
			"Fallback jacket ignores the outfit cloth specular")
	var skin := driver.find_child("HeadMesh", true, false) as MeshInstance3D
	if skin != null:
		_check(absf((skin.material_override as StandardMaterial3D).roughness - outfit.skin_roughness) <= 0.01,
			"Fallback skin ignores the outfit skin roughness")
	remove_child(rig)
	rig.free()
	remove_child(driver)
	driver.free()

func _measure_shared_equipment(controller: SkierAnimationController) -> void:
	# build_boot/build_ski/build_pole/build_sleeves are shared by both rigs:
	# pole tip taper, basket proportion, heel seating, buckle wrap, ski width
	# envelope honesty, and visible sleeve bulk/cuff flare.
	var boot := controller.find_child("LeftBootMesh", true, false) as MeshInstance3D
	var heel := controller.find_child("LeftBootHeel", true, false) as MeshInstance3D
	var buckle := controller.find_child("LeftBootBuckle1", true, false) as MeshInstance3D
	var cuff_boot := controller.find_child("LeftBootCuff", true, false) as MeshInstance3D
	var ski := controller.find_child("LeftSkiMesh", true, false) as MeshInstance3D
	var shaft := controller.find_child("LeftPoleMesh", true, false) as MeshInstance3D
	var basket := controller.find_child("LeftPoleBasket", true, false) as MeshInstance3D
	var point := controller.find_child("LeftPolePoint", true, false) as MeshInstance3D
	_check(boot != null and heel != null and buckle != null and cuff_boot != null
		and ski != null and shaft != null and basket != null and point != null,
		"Shared boot/ski/pole equipment meshes are missing")
	if point != null:
		var tip := point.mesh as CylinderMesh
		_check(tip != null and tip.top_radius >= tip.bottom_radius,
			"Pole tip widens downward (top %.4f bottom %.4f)" % [tip.top_radius if tip != null else 0.0, tip.bottom_radius if tip != null else 0.0])
	if shaft != null and basket != null:
		var shaft_mesh := shaft.mesh as CylinderMesh
		var basket_mesh := basket.mesh as CylinderMesh
		var shaft_r := shaft_mesh.top_radius if shaft_mesh != null else 0.014
		var basket_r := basket_mesh.top_radius if basket_mesh != null else 0.065
		print("CHARACTER_SCALE_MEASURE basket_shaft_ratio=%.3f" % (basket_r / maxf(shaft_r, 0.001)))
		_check(basket_r / maxf(shaft_r, 0.001) <= 6.0,
			"Pole basket (r %.4f) is disproportionate to the shaft (r %.4f)" % [basket_r, shaft_r])
	if boot != null and heel != null:
		# Mesh AABBs are unit-centered: shift into the shared mount frame.
		var boot_box := AABB(boot.get_aabb().position + boot.position, boot.get_aabb().size)
		var heel_box := AABB(heel.get_aabb().position + heel.position, heel.get_aabb().size)
		var overlap := minf(boot_box.end.z, heel_box.end.z) - maxf(boot_box.position.z, heel_box.position.z)
		print("CHARACTER_SCALE_MEASURE heel_overlap=%.4f heel_len=%.4f" % [overlap, heel_box.size.z])
		_check(overlap / maxf(heel_box.size.z, 0.001) >= 0.25,
			"Boot heel cantilevers off the shell (overlap %.1f%%)" % [overlap / maxf(heel_box.size.z, 0.001) * 100.0])
	if buckle != null and cuff_boot != null:
		var buckle_w := (buckle.mesh as BoxMesh).size.x if (buckle.mesh as BoxMesh) != null else 0.215
		var cuff_w := (cuff_boot.mesh as BoxMesh).size.x if (cuff_boot.mesh as BoxMesh) != null else 0.18
		_check(buckle_w <= cuff_w + 0.01,
			"Boot buckles (%.4fm) float past the cuff (%.4fm) with no strap" % [buckle_w, cuff_w])
	if ski != null:
		var ski_w := ski.get_aabb().size.x
		print("CHARACTER_SCALE_MEASURE ski_envelope=%.4f claimed=%.4f" % [ski_w, SkierEquipment.SKI_SIZE.x])
		_check(absf(SkierEquipment.SKI_SIZE.x - ski_w) <= 0.005,
			"SKI_SIZE width (%.4fm) misstates the built ski (%.4fm)" % [SkierEquipment.SKI_SIZE.x, ski_w])
	# Sleeve-vs-arm bulk only exists as authored geometry on the primitive rig.
	var driver := SkierPoseDriver.new()
	add_child(driver)
	driver.build()
	var rig := PrimitiveSkierRig.new()
	add_child(rig)
	if rig.configure(driver):
		var upper_arm := driver.find_child("LeftUpperArm", true, false) as MeshInstance3D
		var upper_sleeve := driver.find_child("LeftUpperSleeve", true, false) as MeshInstance3D
		var forearm_sleeve := driver.find_child("LeftForearmSleeve", true, false) as MeshInstance3D
		var sleeve_cuff := driver.find_child("LeftSleeveCuff", true, false) as MeshInstance3D
		if upper_arm != null and upper_sleeve != null and forearm_sleeve != null and sleeve_cuff != null:
			var arm_r := (upper_arm.mesh as CapsuleMesh).radius
			var sleeve_r := (upper_sleeve.mesh as CapsuleMesh).radius
			var forearm_r := (forearm_sleeve.mesh as CapsuleMesh).radius
			var cuff_r := (sleeve_cuff.mesh as CapsuleMesh).radius
			print("CHARACTER_SCALE_MEASURE sleeve_bulk=%.4f cuff_vs_sleeve=%.4f" % [sleeve_r - arm_r, cuff_r - forearm_r])
			_check(sleeve_r - arm_r >= 0.01,
				"Arm sleeve adds no readable bulk over the arm (%.1fmm)" % [(sleeve_r - arm_r) * 1000.0])
			_check(cuff_r >= forearm_r,
				"Sleeve cuff (r %.4f) is narrower than the forearm sleeve (r %.4f)" % [cuff_r, forearm_r])
		else:
			_check(false, "Primitive sleeve/arm meshes are missing for the bulk check")
	else:
		_check(false, "Primitive rig failed to configure for the sleeve check")
	remove_child(rig)
	rig.free()
	remove_child(driver)
	driver.free()

func _measure_bare_driver_details() -> void:
	# Jacket details are validated in the rest-pose driver frame (identity
	# rotations), where seating reduces to axis offsets against the known
	# torso ellipsoid measured straight from the built mesh.
	var driver := SkierPoseDriver.new()
	add_child(driver)
	driver.build()
	var rig := PrimitiveSkierRig.new()
	add_child(rig)
	if not rig.configure(driver):
		_check(false, "Primitive rig failed to configure for the detail check")
		remove_child(rig)
		rig.free()
		remove_child(driver)
		driver.free()
		return
	await get_tree().process_frame
	var torso := driver.find_child("TorsoMesh", true, false) as MeshInstance3D
	var cuff := driver.find_child("LeftSleeveCuff", true, false) as MeshInstance3D
	var glove := driver.find_child("LeftGlove", true, false) as MeshInstance3D
	var sleeve := driver.find_child("LeftUpperSleeve", true, false) as MeshInstance3D
	var pad := driver.find_child("ShoulderJacket", true, false) as MeshInstance3D
	if torso != null and cuff != null and glove != null:
		var cuff_bottom := cuff.global_position.y - cuff.get_aabb().size.y * 0.5
		var glove_bottom := glove.global_position.y - glove.get_aabb().size.y * 0.5
		print("CHARACTER_SCALE_MEASURE cuff_bottom=%.4f glove_bottom=%.4f" % [cuff_bottom, glove_bottom])
		_check(glove_bottom + 0.035 <= cuff_bottom,
			"Sleeve cuff swallows the glove (only %.1fmm protrudes)" % [(cuff_bottom - glove_bottom) * -1000.0])
	if sleeve != null and pad != null:
		var sleeve_top := sleeve.global_position.y + sleeve.get_aabb().size.y * 0.5
		var pad_top := pad.global_position.y + pad.get_aabb().size.y * 0.5
		_check(sleeve_top <= pad_top + 0.005,
			"Arm sleeve pokes %.1fmm above the shoulder pad" % [(sleeve_top - pad_top) * 1000.0])
	if torso != null:
		var center := torso.global_position + torso.get_aabb().get_center()
		var radii := torso.get_aabb().size * 0.5
		_check_detail_seating(driver, "JacketBackStripe", center, radii, true)
		_check_detail_seating(driver, "JacketFrontZip", center, radii, false)
		_check_detail_seating(driver, "JacketChestPocket", center, radii, false)
	remove_child(rig)
	rig.free()
	remove_child(driver)
	driver.free()

func _check_detail_seating(driver: SkierPoseDriver, part_name: String, center: Vector3, radii: Vector3, is_back: bool) -> void:
	var part := driver.find_child(part_name, true, false) as MeshInstance3D
	_check(part != null, "Jacket detail is missing: " + part_name)
	if part == null:
		return
	var box := part.mesh as BoxMesh
	_check(box != null, part_name + " is not a BoxMesh")
	if box == null:
		return
	var p := part.global_position
	var nx := (p.x - center.x) / maxf(radii.x, 0.001)
	var ny := (p.y - center.y) / maxf(radii.y, 0.001)
	var in_face := 1.0 - nx * nx - ny * ny
	_check(in_face > 0.0, part_name + " sits past the torso silhouette")
	if in_face <= 0.0:
		return
	var surface_z := center.z + (radii.z if is_back else -radii.z) * sqrt(in_face)
	var inner := p.z - box.size.z * 0.5 if is_back else p.z + box.size.z * 0.5
	var gap := (surface_z - inner) if is_back else (inner - surface_z)
	print("CHARACTER_SCALE_MEASURE %s gap=%.4f" % [part_name, gap])
	# Positive gap = embedded behind the skin, negative = floating ahead.
	_check(gap >= -0.002 and gap <= 0.006,
		"%s is mis-seated on the torso shell (gap %.1fmm)" % [part_name, gap * 1000.0])

func _check_region_materials() -> void:
	var outfit := preload("res://resources/character/default_skier_outfit_profile.tres") as SkierOutfitProfile
	_check(outfit != null, "Default outfit profile is missing for the material check")
	if outfit == null:
		return
	var jacket := SkierEquipment.region_surface("Jacket", outfit)
	_check(jacket.resource_name == "Outfit_Jacket" and jacket.albedo_color.is_equal_approx(outfit.jacket_color),
		"Region mapping changed the Jacket surface")
	var pants := SkierEquipment.region_surface("Pants", outfit)
	_check(pants.resource_name == "Outfit_Pants" and pants.albedo_color.is_equal_approx(outfit.pants_color),
		"Region mapping changed the Pants surface")
	var skin := SkierEquipment.region_surface("Skin", outfit)
	_check(skin.resource_name == "Outfit_Skin" and skin.albedo_color.is_equal_approx(outfit.skin_color),
		"Region mapping changed the Skin surface")
	var unmarked := SkierEquipment.region_surface("", outfit)
	print("CHARACTER_SCALE_MEASURE unmarked=%s #%02x%02x%02x" % [unmarked.resource_name,
		int(unmarked.albedo_color.r * 255.0), int(unmarked.albedo_color.g * 255.0), int(unmarked.albedo_color.b * 255.0)])
	_check(unmarked.resource_name == "Outfit_Unmarked",
		"Unmarked import regions are mislabeled " + unmarked.resource_name)
	_check(not unmarked.albedo_color.is_equal_approx(outfit.jacket_color),
		"Unmarked import regions silently inherit the jacket coral")

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
