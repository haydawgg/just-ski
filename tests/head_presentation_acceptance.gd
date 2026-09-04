extends Node

## Head-fit regression coverage for the production SkeletonSkierRig headwear and
## the primitive fallback head. Catches the defects visible in close-up captures:
## asymmetric goggle strap, floating nose bridge, ear pads outside the shell,
## forehead gap between helmet rim and goggle top, and oversized goggles.

const SKIER_VISUAL_SCENE := preload("res://player/animation/skier_visual.tscn")

var failures: Array[String] = []

func _ready() -> void:
	var controller := SKIER_VISUAL_SCENE.instantiate() as SkierAnimationController
	add_child(controller)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_GROUND
	frame.grounded = true
	controller.apply_frame(frame, 1.0 / 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_production_headwear(controller)
	_check_primitive_head_size()
	_check_head_stays_alive_in_air()
	_check_spin_spot_wiring()
	_check_grab_head_counter()
	_check_rail_head_leveling()
	_check_tuck_gaze()
	_check_crash_head_follows()
	_check_helper_head_tracking()
	_check_helmet_clearance()
	if failures.is_empty():
		print("HEAD_PRESENTATION_PASS: fit, air/spot/grab/rail/tuck head behavior passed")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("HEAD_PRESENTATION_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(1)

func _check_production_headwear(controller: SkierAnimationController) -> void:
	var adapter := controller.rig_adapter as SkeletonSkierRig
	_check(adapter != null, "Production visual did not select SkeletonSkierRig")
	if adapter == null:
		return
	var helmet := adapter.find_child("HelmetShell", true, false) as MeshInstance3D
	var strap := adapter.find_child("GoggleStrap", true, false) as MeshInstance3D
	var frame_mesh := adapter.find_child("GoggleFrame", true, false) as MeshInstance3D
	var lens := adapter.find_child("GoggleLens", true, false) as MeshInstance3D
	var bridge := adapter.find_child("GoggleNoseBridge", true, false) as MeshInstance3D
	var pad_left := adapter.find_child("HelmetEarPadLeft", true, false) as MeshInstance3D
	var pad_right := adapter.find_child("HelmetEarPadRight", true, false) as MeshInstance3D
	_check(helmet != null, "HelmetShell is missing")
	_check(strap != null, "GoggleStrap is missing")
	_check(frame_mesh != null, "GoggleFrame is missing")
	_check(lens != null, "GoggleLens is missing")
	_check(bridge != null, "GoggleNoseBridge is missing")
	_check(pad_left != null and pad_right != null, "Helmet ear pads are missing")
	if helmet == null or strap == null or lens == null or bridge == null or pad_left == null or pad_right == null:
		return
	var helmet_box := _world_aabb(helmet)
	var strap_box := _world_aabb(strap)
	var lens_box := _world_aabb(lens)
	var bridge_box := _world_aabb(bridge)
	var pad_left_box := _world_aabb(pad_left)
	var pad_right_box := _world_aabb(pad_right)
	# Symmetry is measured about the head-bone axis, not the world origin:
	# the neutral stance already offsets the whole skull ~10mm sideways.
	var head_idx := int(adapter.bone_indices[&"head"])
	var head_axis_x := (adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(head_idx)).origin.x
	var pad_left_rel := pad_left_box.get_center().x - head_axis_x
	var pad_right_rel := pad_right_box.get_center().x - head_axis_x
	print("HEAD_FIT_MEASURE helmet_center=%.4f strap_center=%.4f lens_w=%.4f helmet_w=%.4f" % [
		helmet_box.get_center().x, strap_box.get_center().x, lens_box.size.x, helmet_box.size.x])
	print("HEAD_FIT_MEASURE bridge_gap=%.4f pad_lx=%.4f pad_rx=%.4f rim_front=%.4f" % [
		_point_to_aabb_distance(bridge_box.get_center(), lens_box),
		pad_left_box.get_center().x, pad_right_box.get_center().x,
		SkierEquipment._helmet_edge_height(-PI * 0.5)])
	print("HEAD_FIT_MEASURE pad_sym=%.4f pad_half_x=%.4f strap_sx=%.4f strap_sz=%.4f brim_frame_overlap=%.6f" % [
		pad_left_rel + pad_right_rel,
		pad_left_box.size.x * 0.5,
		strap_box.size.x, strap_box.size.z,
		_aabb_intersection_volume(_world_aabb(adapter.find_child("HelmetBrim", true, false) as MeshInstance3D), _world_aabb(frame_mesh))])
	# 1. Strap must be centered on the helmet (back wrap), not pulled sideways.
	_check(absf(strap_box.get_center().x - helmet_box.get_center().x) <= 0.008,
		"Goggle strap is off-center by %.1fmm (strap %.4f vs helmet %.4f)" % [
			absf(strap_box.get_center().x - helmet_box.get_center().x) * 1000.0,
			strap_box.get_center().x, helmet_box.get_center().x])
	# 2. Nose bridge must touch the lens surface, not float ahead of it.
	_check(_point_to_aabb_distance(bridge_box.get_center(), lens_box) <= 0.022,
		"Nose bridge floats %.1fmm off the lens surface" % [
			_point_to_aabb_distance(bridge_box.get_center(), lens_box) * 1000.0])
	# 3. Ear pads must sit against the head inside the shell width.
	_check(absf(pad_left_box.get_center().x) <= 0.15 and absf(pad_right_box.get_center().x) <= 0.15,
		"Ear pads float outside the shell (left %.4f right %.4f)" % [
			pad_left_box.get_center().x, pad_right_box.get_center().x])
	_check(pad_left_box.size.x <= 0.04 and pad_right_box.size.x <= 0.04,
		"Ear pads are too bulky (%.4fm)" % pad_left_box.size.x)
	# 4. Helmet front rim must overlap the goggle top: no forehead gap.
	_check(SkierEquipment._helmet_edge_height(-PI * 0.5) <= 0.19,
		"Helmet front rim %.4f leaves a forehead gap above the goggle top" % SkierEquipment._helmet_edge_height(-PI * 0.5))
	# 5. Goggles must not be wider than the helmet shell.
	_check(lens_box.size.x <= helmet_box.size.x,
		"Goggle lens (%.4fm) is wider than the helmet shell (%.4fm)" % [lens_box.size.x, helmet_box.size.x])
	_check_mouth(adapter)
	_check_lens_readability(adapter)
	_check_head_landmark_covers_dome(adapter)
	# 6. Ear pads must be symmetric about the skull axis, not the world origin.
	_check(absf(pad_left_rel + pad_right_rel) <= 0.008,
		"Ear pads are lopsided (left %.4f right %.4f rel skull, sum %.1fmm)" % [
			pad_left_rel, pad_right_rel,
			(pad_left_rel + pad_right_rel) * 1000.0])
	# 7. Pads must be slim liners filling the head-to-shell gap, not buried blocks.
	_check(pad_left_box.size.x * 0.5 <= 0.016 and pad_right_box.size.x * 0.5 <= 0.016,
		"Ear pads are too thick to sit between head and shell (half-width %.4fm)" % (pad_left_box.size.x * 0.5))
	var pad_span := maxf(absf(pad_left_rel), absf(pad_right_rel))
	_check(pad_span >= 0.10 and pad_span <= 0.145,
		"Ear pads sit off the head surface (span %.4fm, expected 0.10-0.145m)" % pad_span)
	# 8. Strap must clear the skull AND reach the shell (ride over it, not inside it).
	_check(strap_box.size.x >= 0.30 and strap_box.size.z >= 0.22,
		"Goggle strap is buried inside the helmet (%.3fx%.3fm)" % [strap_box.size.x, strap_box.size.z])
	# 9. Visor lip must rest on the brow, not interpenetrate the goggle frame.
	var brim := adapter.find_child("HelmetBrim", true, false) as MeshInstance3D
	_check(brim != null, "HelmetBrim is missing")
	if brim != null:
		var overlap := _aabb_intersection_volume(_world_aabb(brim), _world_aabb(frame_mesh))
		_check(overlap <= 0.00008,
			"Visor lip interpenetrates the goggle frame (overlap %.1fcm^3)" % (overlap * 1000000.0))

func _check_mouth(adapter: SkeletonSkierRig) -> void:
	# Stylized mouth line: present, centered on the skull axis, and seated
	# against the runtime-sampled face wall (not a guessed depth).
	var mouth := adapter.find_child("Mouth", true, false) as MeshInstance3D
	_check(mouth != null, "Stylized mouth is missing from the head mount")
	if mouth == null:
		return
	var head_idx := int(adapter.bone_indices[&"head"])
	var head_x := (adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(head_idx)).origin.x
	_check(absf(mouth.global_position.x - head_x) <= 0.003,
		"Mouth is off-center (%.1fmm)" % [(mouth.global_position.x - head_x) * 1000.0])
	var wall := INF
	var sample_count := 0
	for node: Node in adapter.body_root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.skin == null and instance.skeleton.is_empty():
			continue
		for surface_index: int in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var w: Vector3 = instance.global_transform * v
				if absf(w.x - mouth.global_position.x) > 0.10 or absf(w.y - mouth.global_position.y) > 0.10:
					continue
				sample_count += 1
				# Reference is the most-forward skin near mouth height (nose/lip
				# mass): the mouth must not hover ahead of the face. Fine
				# seating against the local wall is verified in close-ups.
				if absf(w.y - mouth.global_position.y) > 0.05:
					continue
				wall = minf(wall, w.z)
	print("HEAD_FIT_MEASURE mouth_at=%.4f,%.4f,%.4f samples=%d" % [
		mouth.global_position.x, mouth.global_position.y, mouth.global_position.z, sample_count])
	_check(wall < INF, "No face wall sampled at the mouth line")
	if wall >= INF:
		return
	var gap := (mouth.global_position.z - 0.006) - wall
	print("HEAD_FIT_MEASURE mouth_gap=%.4f" % gap)
	_check(gap <= 0.005 and gap >= -0.06,
		"Mouth floats off the face (gap %.1fmm)" % (gap * 1000.0))

func _check_lens_readability(adapter: SkeletonSkierRig) -> void:
	# The lens must stay a readable cyan panel, not a mirror: bound the
	# response that washes it to white in snow glare, and keep separation
	# from the near-black frame.
	var lens := adapter.find_child("GoggleLens", true, false) as MeshInstance3D
	var frame_mesh := adapter.find_child("GoggleFrame", true, false) as MeshInstance3D
	_check(lens != null and frame_mesh != null, "Goggle lens/frame are missing for the readability check")
	if lens == null or frame_mesh == null:
		return
	var lens_mat := lens.material_override as StandardMaterial3D
	var frame_mat := frame_mesh.material_override as StandardMaterial3D
	_check(lens_mat != null and frame_mat != null, "Goggle lens/frame have no override materials")
	if lens_mat == null or frame_mat == null:
		return
	print("HEAD_FIT_MEASURE lens rough=%.3f metallic=%.3f spec=%.3f" % [
		lens_mat.roughness, lens_mat.metallic, lens_mat.metallic_specular])
	_check(lens_mat.roughness >= 0.20 and lens_mat.roughness <= 0.35,
		"Goggle lens roughness %.3f leaves the mirror-glare range" % lens_mat.roughness)
	_check(lens_mat.metallic >= 0.20 and lens_mat.metallic <= 0.40,
		"Goggle lens metallic %.3f leaves the readable range" % lens_mat.metallic)
	var la := lens_mat.albedo_color
	var fa := frame_mat.albedo_color
	var separation := Vector3(la.r - fa.r, la.g - fa.g, la.b - fa.b).length()
	_check(separation >= 0.50,
		"Lens/frame albedo separation %.3f is too low to read" % separation)

func _check_head_landmark_covers_dome(adapter: SkeletonSkierRig) -> void:
	# The head landmark feeds camera framing and silhouette height: it must
	# clear the helmet dome, not clip 6cm below it.
	var head_idx := int(adapter.bone_indices[&"head"])
	var bone := (adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(head_idx)).origin
	var marks := adapter.landmarks()
	_check(marks.has("head"), "Head landmark is missing")
	if not marks.has("head"):
		return
	var clearance := (marks["head"] as Vector3).y - bone.y
	print("HEAD_FIT_MEASURE landmark_clearance=%.4f" % clearance)
	_check(clearance >= 0.28,
		"Head landmark clips %.1fmm below the helmet dome" % [(0.28 - clearance) * 1000.0])

func _check_primitive_head_size() -> void:
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
	var head := driver.find_child("HeadMesh", true, false) as MeshInstance3D
	_check(head != null, "Primitive fallback HeadMesh is missing")
	if head != null:
		var sphere := head.mesh as SphereMesh
		_check(sphere != null, "Primitive HeadMesh is not a SphereMesh")
		if sphere != null:
			print("HEAD_FIT_MEASURE primitive_head_radius=%.4f" % sphere.radius)
			_check(sphere.radius <= 0.13,
				"Primitive head radius %.4fm swallows the shared helmet shell (inner 0.152m)" % sphere.radius)
			_check(sphere.radius >= 0.09,
				"Primitive head radius %.4fm is too small to read at gameplay distance" % sphere.radius)
	var jaw := driver.find_child("JawMesh", true, false) as MeshInstance3D
	var mouth := driver.find_child("Mouth", true, false) as MeshInstance3D
	_check(jaw != null, "Primitive JawMesh is missing")
	_check(mouth != null, "Primitive mouth is missing")
	if jaw != null and mouth != null:
		_check(absf(mouth.global_position.x) <= 0.003,
			"Primitive mouth is off-center (%.1fmm)" % (mouth.global_position.x * 1000.0))
		var radii := jaw.get_aabb().size * 0.5
		var c := jaw.global_position + jaw.get_aabb().get_center()
		var p := mouth.global_position
		var f := 1.0 - pow((p.x - c.x) / maxf(radii.x, 0.001), 2.0) - pow((p.y - c.y) / maxf(radii.y, 0.001), 2.0)
		_check(f > 0.0, "Primitive mouth sits past the jaw silhouette")
		if f > 0.0:
			var gap := (p.z + 0.006) - (c.z - radii.z * sqrt(f))
			print("HEAD_FIT_MEASURE primitive_mouth_gap=%.4f" % gap)
			_check(gap >= -0.002 and gap <= 0.006,
				"Primitive mouth floats off the jaw (gap %.1fmm)" % (gap * 1000.0))
	remove_child(rig)
	rig.free()
	remove_child(driver)
	driver.free()

func _check_head_stays_alive_in_air() -> void:
	# Straight air must keep a declared head attitude (look + style bias) and
	# keep the takeoff side instead of snapping to a zeroed mannequin head.
	var rig := SkierAnimationController.new()
	add_child(rig)
	var ground := _ground_frame()
	ground.edge = 1.0
	ground.turn_input = 1.0
	ground.turn_rate = 0.9
	ground.lateral_acceleration = 11.0
	_step(rig, ground, 60)
	var ground_yaw := _head_rotation(rig).y
	var air := _air_frame()
	_step(rig, air, 90)
	var settled := _head_rotation(rig)
	print("HEAD_MOTION_MEASURE air_head=%.4f,%.4f,%.4f ground_yaw=%.4f" % [settled.x, settled.y, settled.z, ground_yaw])
	_check(absf(settled.x) + absf(settled.y) > 0.06,
		"Straight-air head is dead (pitch %.4f yaw %.4f)" % [settled.x, settled.y])
	_check(signf(settled.y) == signf(ground_yaw),
		"Air head lost the takeoff side (air yaw %.4f vs ground yaw %.4f)" % [settled.y, ground_yaw])
	remove_child(rig)
	rig.free()

func _check_spin_spot_wiring() -> void:
	# profile.spin_head_spot must actually drive the spin head lead: zeroing
	# the knob has to shrink the head yaw, or the export is dead.
	var with_spot := _spin_head_yaw(0.68)
	var without_spot := _spin_head_yaw(0.0)
	print("HEAD_MOTION_MEASURE spin_head_yaw spot=0.68:%.4f spot=0:%.4f" % [with_spot, without_spot])
	_check(with_spot > 0.05 and signf(with_spot) > 0.0,
		"Spin head does not lead into a right spin (yaw %.4f)" % with_spot)
	_check(with_spot - without_spot > 0.01,
		"spin_head_spot is not wired (yaw %.4f with and without the knob)" % with_spot)

func _spin_head_yaw(spot: float) -> float:
	var rig := SkierAnimationController.new()
	add_child(rig)
	var alt := rig.profile.duplicate() as SkierAnimationProfile
	alt.spin_head_spot = spot
	rig.profile = alt
	var frame := _air_frame()
	frame.trick_active = true
	frame.trick_intent = true
	frame.trick_kind = TrickCommand.Kind.SPIN_RIGHT
	frame.trick_phase = TrickCommand.PresentationPhase.ROTATE
	frame.angular_velocity = Vector3(0.0, 5.4, 0.0)
	frame.rotation_accumulated = Vector3(0.0, PI, 0.0)
	_step(rig, frame, 90)
	var yaw := _head_rotation(rig).y
	remove_child(rig)
	rig.free()
	return yaw

func _check_grab_head_counter() -> void:
	# Japan folds spine -0.4 / chest -0.24 with no authored head look; the gaze
	# must counter-pitch forward instead of burying the face in the knees.
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _air_frame()
	frame.grab_pose = TrickController.GrabPose.JAPAN_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.8
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	_step(rig, frame, 140)
	var pitch := _head_rotation(rig).x
	print("HEAD_MOTION_MEASURE japan_head_pitch=%.4f" % pitch)
	_check(pitch > 0.1,
		"Grab head does not counter the torso fold (pitch %.4f during Japan hold)" % pitch)
	remove_child(rig)
	rig.free()

func _check_rail_head_leveling() -> void:
	# On a hard balance offset the head must counter-roll like the carve
	# head-level, not inherit the chest roll (broken-neck read).
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 2
	frame.speed_mps = 13.0
	frame.speed_ratio = 0.55
	frame.rail_speed = 13.0
	frame.rail_pose = 0
	frame.rail_distance_to_end = 5.0
	frame.rail_balance = 1.0
	_step(rig, frame, 120)
	var roll := _head_rotation(rig).z
	print("HEAD_MOTION_MEASURE rail_head_roll=%.4f" % roll)
	_check(roll > 0.03,
		"Rail head does not level against the balance offset (roll %.4f)" % roll)
	remove_child(rig)
	rig.free()

func _check_tuck_gaze() -> void:
	# Full tuck pitches the torso ~1.06 rad forward; the head must compensate
	# so the gaze lands on the hill ahead, not on the skis.
	var rig := SkierAnimationController.new()
	add_child(rig)
	var frame := _ground_frame()
	frame.speed_mps = 25.0
	frame.speed_ratio = 1.0
	frame.tuck = 1.0
	_step(rig, frame, 120)
	var pitch := _head_rotation(rig).x
	print("HEAD_MOTION_MEASURE tuck_head_pitch=%.4f" % pitch)
	_check(pitch > 0.5,
		"Tuck gaze stays on the skis (head pitch %.4f)" % pitch)
	remove_child(rig)
	rig.free()

func _check_crash_head_follows() -> void:
	# Bail stages all declare tumbling head poses; the head must stay engaged
	# with the fall rather than freezing while the body tumbles.
	var rig := SkierAnimationController.new()
	add_child(rig)
	var worst := 1.0
	for stage: int in [CrashContext.Stage.IMPACT, CrashContext.Stage.FALL, CrashContext.Stage.REST]:
		var frame := SkierAnimationFrame.new()
		frame.locomotion_state = SkierAnimationController.STATE_BAIL
		frame.crash_reason = CrashContext.Reason.FEATURE_IMPACT
		frame.crash_stage = stage
		frame.crash_elapsed = 0.18 if stage == CrashContext.Stage.IMPACT else (0.7 if stage == CrashContext.Stage.FALL else 1.4)
		frame.crash_incoming_velocity = Vector3(6.0, -3.0, -14.0)
		frame.crash_current_velocity = Vector3(5.0, -2.0, -11.0)
		frame.crash_impact_speed = 9.0
		frame.crash_lateral_bias = 1.0
		frame.crash_angular_speed = 4.5
		frame.crash_rest_detected = stage == CrashContext.Stage.REST
		_step(rig, frame, 60)
		worst = minf(worst, _head_rotation(rig).length())
	print("HEAD_MOTION_MEASURE crash_head_min=%.4f" % worst)
	_check(worst > 0.05,
		"Crash head freezes during the tumble (min magnitude %.4f)" % worst)
	remove_child(rig)
	rig.free()

func _check_helper_head_tracking() -> void:
	# During a cross-body MUTE hold the production upper-spine assist (1.0)
	# drags the head with the thorax. Assist drag = growth in the
	# production-vs-canonical head angle from rest to hold; the rest offset
	# itself is legitimate retarget difference (bind pose, model yaw).
	var rig := SkierAnimationController.new()
	add_child(rig)
	_step(rig, _air_frame(), 30)
	var rest := _head_world_pair(rig)
	var frame := _air_frame()
	frame.grab_pose = TrickController.GrabPose.MUTE_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.8
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	_step(rig, frame, 140)
	var held := _head_world_pair(rig)
	var dp := ((held[0] as Quaternion) * (rest[0] as Quaternion).inverse()).normalized()
	var dc := ((held[1] as Quaternion) * (rest[1] as Quaternion).inverse()).normalized()
	var drag := 2.0 * acos(clampf(absf(dp.dot(dc)), -1.0, 1.0))
	print("HEAD_MOTION_MEASURE helper_head_drift=%.4f" % drag)
	_check(drag <= 0.25,
		"Grab assist drags the production head off canonical (drift %.4f rad)" % drag)
	remove_child(rig)
	rig.free()

func _head_world_pair(rig: SkierAnimationController) -> Array:
	# [production head world quat, canonical head world quat]. Callers compare
	# rest-to-hold DELTAS, never absolute orientations (bind poses differ).
	var adapter := rig.rig_adapter as SkeletonSkierRig
	if adapter == null or rig.pose_driver == null:
		return [Quaternion.IDENTITY, Quaternion.IDENTITY]
	var production := (adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(int(adapter.bone_indices[&"head"]))).basis.orthonormalized().get_rotation_quaternion()
	var canonical := rig.pose_driver.joint(&"head").global_transform.basis.orthonormalized().get_rotation_quaternion()
	return [production, canonical]

func _head_rotation(rig: SkierAnimationController) -> Vector3:
	return rig.debug_snapshot().get("head_rotation", Vector3.ZERO) as Vector3

func _check_helmet_clearance() -> void:
	# Deep folds (Japan hold, crash FALL) must not drive the helmet shell into
	# the torso/limbs: minimum point-to-box distance from the helmet to the
	# major body landmarks stays positive.
	var worst := INF
	worst = minf(worst, _helmet_gap(_japan_hold_frame(), 140, "japan"))
	worst = minf(worst, _helmet_gap(_crash_frame(CrashContext.Stage.FALL, 0.7), 60, "fall"))
	_check(worst > 0.02,
		"Helmet shell interpenetrates the body in deep folds (gap %.1fmm)" % (worst * 1000.0))

func _helmet_gap(frame: SkierAnimationFrame, steps: int, label: String) -> float:
	var rig := SkierAnimationController.new()
	add_child(rig)
	_step(rig, frame, steps)
	var gap := INF
	var adapter := rig.rig_adapter as SkeletonSkierRig
	if adapter != null:
		var helmet := adapter.find_child("HelmetShell", true, false) as MeshInstance3D
		var marks := adapter.landmarks()
		if helmet != null:
			var box := _world_aabb(helmet)
			for key: String in ["pelvis", "left_knee", "right_knee", "left_boot", "right_boot"]:
				if marks.has(key):
					gap = minf(gap, _point_to_aabb_distance(marks[key] as Vector3, box))
	print("HEAD_MOTION_MEASURE helmet_gap_%s=%.4f" % [label, gap])
	remove_child(rig)
	rig.free()
	return gap

func _japan_hold_frame() -> SkierAnimationFrame:
	var frame := _air_frame()
	frame.grab_pose = TrickController.GrabPose.JAPAN_LEFT
	frame.grab_amount = 1.0
	frame.grab_input_strength = 1.0
	frame.grab_hold_time = 0.8
	frame.trick_phase = TrickCommand.PresentationPhase.GRAB
	return frame

func _crash_frame(stage: int, elapsed: float) -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = SkierAnimationController.STATE_BAIL
	frame.crash_reason = CrashContext.Reason.FEATURE_IMPACT
	frame.crash_stage = stage
	frame.crash_elapsed = elapsed
	frame.crash_incoming_velocity = Vector3(6.0, -3.0, -14.0)
	frame.crash_current_velocity = Vector3(5.0, -2.0, -11.0)
	frame.crash_impact_speed = 9.0
	frame.crash_lateral_bias = 1.0
	frame.crash_angular_speed = 4.5
	frame.crash_rest_detected = stage == CrashContext.Stage.REST
	return frame
func _ground_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 0
	frame.grounded = true
	frame.speed_mps = 20.0
	frame.speed_ratio = 1.0
	frame.contact_confidence = 1.0
	frame.left_contact_confidence = 1.0
	frame.right_contact_confidence = 1.0
	frame.left_grounded = true
	frame.right_grounded = true
	frame.left_ground_distance = frame.seat_distance
	frame.right_ground_distance = frame.seat_distance
	return frame

func _air_frame() -> SkierAnimationFrame:
	var frame := SkierAnimationFrame.new()
	frame.locomotion_state = 1
	frame.grounded = false
	frame.speed_mps = 18.0
	frame.speed_ratio = 0.8
	frame.takeoff_type = SkierAnimationFrame.TakeoffType.CHARGED_POP
	frame.takeoff_charge = 0.9
	frame.takeoff_upward_speed = 4.0
	frame.air_time = 0.55
	frame.air_upward_velocity = 0.0
	frame.predicted_landing_time = 0.52
	return frame

func _step(rig: SkierAnimationController, frame: SkierAnimationFrame, count: int) -> void:
	for _index: int in count:
		rig.apply_frame(frame, 1.0 / 60.0)

func _world_aabb(instance: MeshInstance3D) -> AABB:
	var local: AABB = instance.get_aabb()
	var result := AABB()
	var initialized := false
	for x: int in [0, 1]:
		for y: int in [0, 1]:
			for z: int in [0, 1]:
				var p := local.position + Vector3(local.size.x * x, local.size.y * y, local.size.z * z)
				var w: Vector3 = instance.global_transform * p
				if not initialized:
					result = AABB(w, Vector3.ZERO)
					initialized = true
				else:
					result = result.expand(w)
	return result

func _point_to_aabb_distance(point: Vector3, box: AABB) -> float:
	var clamped := Vector3(
		clampf(point.x, box.position.x, box.end.x),
		clampf(point.y, box.position.y, box.end.y),
		clampf(point.z, box.position.z, box.end.z))
	return point.distance_to(clamped)

func _aabb_intersection_volume(a: AABB, b: AABB) -> float:
	var overlap := a.intersection(b)
	if overlap.size.x <= 0.0 or overlap.size.y <= 0.0 or overlap.size.z <= 0.0:
		return 0.0
	return overlap.size.x * overlap.size.y * overlap.size.z

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
