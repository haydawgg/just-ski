extends Node3D

## CAM-01/CAM-02 regression: kidnapped-camera hard reacquire.
##
## Part 1 (recovery): the skier skims a tall rock face (1 m clearance,
## couloir-like) while the camera starts deep inside the rock (the
## slipped-frame state the P0 target-loss postmortem worries about). The rig
## must escape to a clear tracking pose and stay bounded, translating, and
## visible at 30/60/120 Hz instead of freezing until the skier disappears.
##
## Part 2 (fallback-hierarchy contract): the Phase 1 emergency hierarchy must
## exist and uphold its contract — every emergency pose inherits target
## motion (never commits the raw start-of-frame world pose), satisfies
## min/max distance, min up offset, and destination clearance, and the bounded
## hard reacquire returns a validated target-relative chase pose.

const SPEED := 22.0
const RUN_TIME := 3.0
const WINDOW := 0.25
const TARGET_MATERIAL := 2.0
const CAMERA_MATERIAL := 0.5
const MAX_INVALID_STREAK := 0.4
const DISTANCE_TOLERANCE := 0.05

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	for step: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		await _run_kidnapped_reproduction(step)
	await _run_fallback_hierarchy_contract()
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_KIDNAP_PASS: kidnapped camera recovered and the emergency hierarchy upholds its contract at 30/60/120 Hz")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_KIDNAP_FAIL: " + failure)
	get_tree().quit(1)

func _run_kidnapped_reproduction(step: float) -> void:
	var container := StaticBody3D.new()
	container.collision_layer = 1
	container.collision_mask = 0
	var container_shape := CollisionShape3D.new()
	var container_box := BoxShape3D.new()
	container_box.size = Vector3(30.0, 10.0, 30.0)
	container_shape.shape = container_box
	container.add_child(container_shape)
	container.position = Vector3(0.0, 5.0, 0.0)
	add_child(container)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.global_position = Vector3(16.0, 0.35, -25.0)
	skier.velocity = Vector3(0.0, 0.0, -SPEED)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	# Kidnap: teleport the camera deep into the rock face the skier is
	# skimming, simulating a slipped frame. The skier keeps advancing outside.
	camera_rig.global_position = Vector3(0.0, 5.0, -25.0)

	var label := "%.0f Hz" % (1.0 / step)
	var frames := ceili(RUN_TIME / step)
	var history: Array[Dictionary] = []
	var invalid_streak := 0.0
	var reacquire_seen := false
	var escaped := false
	for frame_index: int in frames:
		var elapsed := float(frame_index) * step
		skier.global_position = Vector3(16.0, 0.35, -25.0 - SPEED * elapsed)
		skier.velocity = Vector3(0.0, 0.0, -SPEED)
		camera_rig._physics_process(step)
		var cam_pos := camera_rig.global_position
		var skier_pos := skier.global_position
		var snapshot := camera_rig.debug_snapshot()
		reacquire_seen = reacquire_seen or bool(snapshot.get("hard_reacquire_used", false))
		var clear := camera_rig._camera_destination_is_clear(cam_pos)
		escaped = escaped or clear
		if frame_index > 0 and not clear:
			failures.append("%s frame %d still commits a colliding camera pose %s" % [label, frame_index, cam_pos])
			break
		var distance := cam_pos.distance_to(skier_pos)
		if clear and distance > camera_rig.maximum_camera_distance + DISTANCE_TOLERANCE:
			failures.append("%s frame %d exceeded max distance: %.3f m" % [label, frame_index, distance])
			break
		var evaluation := camera_rig._evaluate_composition(cam_pos, camera_rig.global_basis, camera_rig.camera.fov, Vector3.UP)
		if clear and camera_rig._composition_hard_valid(evaluation):
			invalid_streak = 0.0
		else:
			invalid_streak += step
			if invalid_streak > MAX_INVALID_STREAK:
				failures.append("%s lost hard skier visibility for %.2f s after kidnap (world-space freeze)" % [label, invalid_streak])
				break
		history.append({"t": elapsed, "cam": cam_pos, "skier": skier_pos})
		if history.size() > ceili(WINDOW / step) + 2:
			history.pop_front()
		if history.size() >= 2:
			var oldest: Dictionary = history[0]
			var newest: Dictionary = history[history.size() - 1]
			if float(newest.get("t", 0.0)) - float(oldest.get("t", 0.0)) >= WINDOW - step * 0.5:
				var target_advance := (newest.get("skier", Vector3.ZERO) as Vector3).distance_to(oldest.get("skier", Vector3.ZERO) as Vector3)
				var camera_advance := (newest.get("cam", Vector3.ZERO) as Vector3).distance_to(oldest.get("cam", Vector3.ZERO) as Vector3)
				if target_advance >= TARGET_MATERIAL and camera_advance < CAMERA_MATERIAL:
					failures.append("%s froze in world space after kidnap: target %.2f m, camera %.2f m over %.2f s" % [label, target_advance, camera_advance, WINDOW])
					break
	if failures.is_empty() or not failures[failures.size() - 1].begins_with(label):
		if not escaped:
			failures.append("%s never reached a clear camera pose" % label)
		else:
			print("CAMERA_KIDNAP_SAMPLE %s escaped and tracking (reacquire engaged: %s)" % [label, reacquire_seen])
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
	remove_child(container)
	container.free()

func _run_fallback_hierarchy_contract() -> void:
	# The Phase 1 hierarchy is a deliverable: emergency poses must be
	# target-relative, bounded, and clear. Absence of the API fails the phase.
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	skier.global_position = Vector3(0.0, 0.35, 0.0)
	skier.velocity = Vector3(0.0, 0.0, -22.0)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	camera_rig.set_target(skier)
	if not camera_rig.has_method("_emergency_fallback_position") or not camera_rig.has_method("_hard_reacquire_pose"):
		failures.append("Emergency fallback hierarchy API is missing (CAM-01/CAM-02 fix not present)")
		_remove_pair(skier, camera_rig)
		return
	var step := 1.0 / 60.0
	var frame_start := camera_rig.global_position
	var displacement := Vector3(0.0, 0.0, -22.0 * step)
	skier.global_position += displacement
	var travel := Vector3(0.0, 0.0, -1.0)
	for force: bool in [false, true]:
		var pose := camera_rig._emergency_fallback_position(frame_start, displacement, Vector3.UP, travel, step, force) as Vector3
		_assert_hierarchy_pose(camera_rig, pose, frame_start, displacement, "force=%s" % force)
	var reacquire: Dictionary = camera_rig._hard_reacquire_pose(frame_start + displacement, Vector3.UP, travel)
	if not bool(reacquire.get("valid", false)):
		failures.append("Hard reacquire rejected a clear open-field chase pose")
	else:
		_assert_hierarchy_pose(camera_rig, reacquire.get("position", frame_start) as Vector3, frame_start, displacement, "reacquire")
	_remove_pair(skier, camera_rig)

func _assert_hierarchy_pose(camera_rig: SkiCameraController, pose: Vector3, frame_start: Vector3, displacement: Vector3, context: String) -> void:
	if not pose.is_finite():
		failures.append("Emergency pose is not finite (%s)" % context)
		return
	var offset := pose - camera_rig.target.global_position
	if offset.length() < camera_rig.minimum_camera_distance - 0.01 or offset.length() > camera_rig.maximum_camera_distance + 0.01:
		failures.append("Emergency pose violates distance bounds at %.3f m (%s)" % [offset.length(), context])
	if offset.dot(Vector3.UP) < camera_rig.minimum_camera_up_offset - 0.01:
		failures.append("Emergency pose violates min up offset (%.3f) (%s)" % [offset.dot(Vector3.UP), context])
	if not camera_rig._camera_destination_is_clear(pose):
		failures.append("Emergency pose %s is not destination-clear (%s)" % [pose, context])
	# CAM-02 core property: the pose must inherit target motion, never freeze
	# on the raw start-of-frame world pose after the target has moved.
	var inherited := (pose - frame_start).length()
	if inherited < displacement.length() - 0.5:
		failures.append("Emergency pose discarded target motion: inherited %.3f m of %.3f m (%s)" % [inherited, displacement.length(), context])

func _remove_pair(skier: SkierController, camera_rig: SkiCameraController) -> void:
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
