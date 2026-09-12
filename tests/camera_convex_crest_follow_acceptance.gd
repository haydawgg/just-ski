extends Node3D

## CAM-01/CAM-02 regression: sustained convex-crest AIR -> LANDING -> GROUND
## follow at realistic high speed.
##
## A skier drops over a convex plateau edge (10 m above the landing slope)
## while the plateau block sits between the trailing camera and all future
## desired poses. The camera must shorten its chase arm and keep following
## (controlled pull-in) instead of freezing in world space until the skier
## disappears. Runs at 30/60/120 Hz on real curved/convex collision geometry.

const APPROACH_SPEED := 22.0
const PLATEAU_TOP := 12.0
const APPROACH_HEIGHT := PLATEAU_TOP + 0.35
const AIR_POP := 1.5
const GRAVITY := 9.8
const SLOPE_GRADE := PLATEAU_TOP / 44.0
const SLOPE_END_Z := -44.0
const WINDOW := 0.25
const TARGET_MATERIAL := 2.0
const CAMERA_MATERIAL := 0.5
const MAX_INVALID_STREAK := 0.4
const DISTANCE_TOLERANCE := 0.05

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	for step: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		await _run_crest_follow_reproduction(step)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("CAMERA_CREST_PASS: convex crest follow stayed bounded, translating, and visible at 30/60/120 Hz")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("CAMERA_CREST_FAIL: " + failure)
	get_tree().quit(1)

func _slope_surface_y(z: float) -> float:
	return PLATEAU_TOP + SLOPE_GRADE * z

func _build_geometry() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	# Tall broad plateau: the convex edge sits 12 m above the landing, and the
	# block extends far uphill so direct, lift, and shoulder sweeps stay
	# blocked for a sustained window while the skier descends past the edge.
	var plateau := StaticBody3D.new()
	plateau.collision_layer = 1
	plateau.collision_mask = 0
	var plateau_shape := CollisionShape3D.new()
	var plateau_box := BoxShape3D.new()
	plateau_box.size = Vector3(30.0, 6.0, 80.0)
	plateau_shape.shape = plateau_box
	plateau.add_child(plateau_shape)
	plateau.position = Vector3(0.0, PLATEAU_TOP - 3.0, 40.0)
	add_child(plateau)
	nodes.append(plateau)
	var slope := StaticBody3D.new()
	slope.collision_layer = 1
	slope.collision_mask = 0
	var slope_shape := CollisionShape3D.new()
	var slope_box := BoxShape3D.new()
	slope_box.size = Vector3(30.0, 1.0, 46.0)
	slope_shape.shape = slope_box
	slope.add_child(slope_shape)
	slope.rotation.x = -atan2(PLATEAU_TOP, 44.0)
	slope.position = Vector3(0.0, 5.47, -22.07)
	add_child(slope)
	nodes.append(slope)
	var runout := StaticBody3D.new()
	runout.collision_layer = 1
	runout.collision_mask = 0
	var runout_shape := CollisionShape3D.new()
	var runout_box := BoxShape3D.new()
	runout_box.size = Vector3(60.0, 1.0, 82.0)
	runout_shape.shape = runout_box
	runout.add_child(runout_shape)
	runout.position = Vector3(0.0, -0.5, -83.0)
	add_child(runout)
	nodes.append(runout)
	return nodes

func _run_crest_follow_reproduction(step: float) -> void:
	var geometry := _build_geometry()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var skier := SkierController.new()
	skier.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(skier)
	var camera_rig := SkiCameraController.new()
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera_rig)
	skier.global_position = Vector3(0.0, APPROACH_HEIGHT, APPROACH_SPEED * 1.2)
	skier.velocity = Vector3(0.0, 0.0, -APPROACH_SPEED)
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.contact.average_normal = Vector3.UP
	camera_rig.set_target(skier)

	var air_time := _solve_air_time()
	var approach_time := 1.2
	var total_time := approach_time + air_time + 5.5
	var frames := ceili(total_time / step)
	var history: Array[Dictionary] = []
	var invalid_streak := 0.0
	var max_invalid_streak := 0.0
	var max_consecutive_emergencies := 0
	var reacquire_seen := false
	var label := "%.0f Hz" % (1.0 / step)
	for frame_index: int in frames:
		var elapsed := float(frame_index) * step
		_drive_skier(skier, elapsed, approach_time, air_time)
		camera_rig._physics_process(step)
		var cam_pos := camera_rig.global_position
		var skier_pos := skier.global_position
		var snapshot := camera_rig.debug_snapshot()
		var distance := cam_pos.distance_to(skier_pos)
		if distance > camera_rig.maximum_camera_distance + DISTANCE_TOLERANCE:
			failures.append("%s frame %d exceeded max distance: %.3f m" % [label, frame_index, distance])
			break
		if not camera_rig._camera_destination_is_clear(cam_pos):
			failures.append("%s frame %d committed a colliding camera pose %s" % [label, frame_index, cam_pos])
			break
		var evaluation := camera_rig._evaluate_composition(cam_pos, camera_rig.global_basis, camera_rig.camera.fov, Vector3.UP)
		if camera_rig._composition_hard_valid(evaluation):
			invalid_streak = 0.0
		else:
			invalid_streak += step
			max_invalid_streak = maxf(max_invalid_streak, invalid_streak)
			if invalid_streak > MAX_INVALID_STREAK:
				failures.append("%s lost hard skier visibility for %.2f s around frame %d (crest/landing freeze)" % [label, invalid_streak, frame_index])
				break
		max_consecutive_emergencies = maxi(max_consecutive_emergencies, int(snapshot.get("consecutive_emergency_frames", 0)))
		reacquire_seen = reacquire_seen or bool(snapshot.get("hard_reacquire_used", false))
		history.append({"t": elapsed, "cam": cam_pos, "skier": skier_pos, "reacquire": reacquire_seen})
		if history.size() > ceili(WINDOW / step) + 2:
			history.pop_front()
		if history.size() >= 2:
			var oldest: Dictionary = history[0]
			var newest: Dictionary = history[history.size() - 1]
			if float(newest.get("t", 0.0)) - float(oldest.get("t", 0.0)) >= WINDOW - step * 0.5:
				var target_advance := (newest.get("skier", Vector3.ZERO) as Vector3).distance_to(oldest.get("skier", Vector3.ZERO) as Vector3)
				var camera_advance := (newest.get("cam", Vector3.ZERO) as Vector3).distance_to(oldest.get("cam", Vector3.ZERO) as Vector3)
				if target_advance >= TARGET_MATERIAL and camera_advance < CAMERA_MATERIAL and not bool(newest.get("reacquire", false)):
					failures.append("%s frames %d-%d froze in world space: target %.2f m, camera %.2f m over %.2f s" % [label, frame_index - history.size() + 1, frame_index, target_advance, camera_advance, WINDOW])
					break
	if failures.is_empty() or not failures[failures.size() - 1].begins_with(label):
		print("CAMERA_CREST_SAMPLE %s air=%.2fs max_invalid_streak=%.2fs max_consecutive_emergencies=%d reacquire=%s" % [label, air_time, max_invalid_streak, max_consecutive_emergencies, reacquire_seen])
		var final_evaluation := camera_rig._evaluate_composition(camera_rig.global_position, camera_rig.global_basis, camera_rig.camera.fov, Vector3.UP)
		if not camera_rig._composition_hard_valid(final_evaluation):
			failures.append("%s never recovered a hard-valid composition after the crest" % label)
	remove_child(camera_rig)
	camera_rig.free()
	remove_child(skier)
	skier.free()
	for node: Node3D in geometry:
		remove_child(node)
		node.free()

func _solve_air_time() -> float:
	# Ballistic y(τ) = APPROACH_HEIGHT + AIR_POP·τ − g/2·τ² meets the landing
	# slope y = PLATEAU_TOP − SLOPE_GRADE·APPROACH_SPEED·τ.
	var a := -GRAVITY * 0.5
	var b := AIR_POP + SLOPE_GRADE * APPROACH_SPEED
	var c := APPROACH_HEIGHT - PLATEAU_TOP
	return (-b - sqrt(b * b - 4.0 * a * c)) / (2.0 * a)

func _drive_skier(skier: SkierController, elapsed: float, approach_time: float, air_time: float) -> void:
	if elapsed < approach_time:
		var z := APPROACH_SPEED * (approach_time - elapsed)
		skier.global_position = Vector3(0.0, APPROACH_HEIGHT, z)
		skier.velocity = Vector3(0.0, 0.0, -APPROACH_SPEED)
		skier.state = SkierController.State.GROUND
		skier.contact.grounded = true
		skier.contact.average_normal = Vector3.UP
		skier.predicted_landing_valid = false
		return
	var tau := elapsed - approach_time
	if tau < air_time:
		skier.global_position = Vector3(0.0, APPROACH_HEIGHT + AIR_POP * tau - 0.5 * GRAVITY * tau * tau, -APPROACH_SPEED * tau)
		skier.velocity = Vector3(0.0, AIR_POP - GRAVITY * tau, -APPROACH_SPEED)
		skier.state = SkierController.State.AIR
		skier.contact.grounded = false
		skier.predicted_landing_valid = true
		skier.predicted_landing_point = Vector3(0.0, _slope_surface_y(-APPROACH_SPEED * air_time), -APPROACH_SPEED * air_time)
		skier.predicted_landing_time = maxf(0.02, air_time - tau)
		return
	# Landed: ride the slope, then the runout floor, and keep skiing.
	var slope_z := -APPROACH_SPEED * air_time
	var slope_dir := Vector3(0.0, -0.2632, -0.9648).normalized()
	var slope_speed := APPROACH_SPEED
	var after := tau - air_time
	var ride_z := slope_z - slope_speed * 0.9648 * after
	if ride_z > SLOPE_END_Z:
		var ridden := slope_dir * slope_speed * after
		skier.global_position = Vector3(0.0, _slope_surface_y(slope_z) + ridden.y + 0.35, slope_z + ridden.z)
		skier.velocity = slope_dir * slope_speed
		skier.contact.average_normal = Vector3(0.0, 0.9648, -0.2632).normalized()
	else:
		var slope_duration := (SLOPE_END_Z - slope_z) / (-slope_speed * 0.9648)
		var floor_after := after - slope_duration
		skier.global_position = Vector3(0.0, 0.35, SLOPE_END_Z - APPROACH_SPEED * floor_after)
		skier.velocity = Vector3(0.0, 0.0, -APPROACH_SPEED)
		skier.contact.average_normal = Vector3.UP
	skier.state = SkierController.State.GROUND
	skier.contact.grounded = true
	skier.predicted_landing_valid = false
