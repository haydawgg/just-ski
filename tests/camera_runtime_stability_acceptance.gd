extends Node

const MAX_FRAMES := 360
const MAX_YAW_STEP_DEGREES := 20.0
const MAX_GROUND_LATERAL_OFFSET := 2.5

@onready var resort: Node = $Resort

var frame := 0
var previous_yaw := 0.0
var max_yaw_step := 0.0
var max_ground_lateral_offset := 0.0

func _ready() -> void:
	var camera := resort.get_node("CameraRig") as SkiCameraController
	_test_atomic_spawn_reset()
	previous_yaw = float(camera.debug_snapshot().get("actual_yaw_degrees", 0.0))

func _test_atomic_spawn_reset() -> void:
	var skier := resort.get_node("Skier") as SkierController
	var camera := resort.get_node("CameraRig") as SkiCameraController
	var spawn := skier.global_transform
	var initial_pose := _visible_pose(skier)
	var initial_camera := camera.global_transform
	skier._update_animation(1.0 / 120.0)
	var first_pose := _visible_pose(skier)
	var startup_step := _pose_distance(initial_pose, first_pose)
	if startup_step > 0.03:
		push_error("CAMERA_RUNTIME_STABILITY_FAIL: spawn presentation moved %.3f m before any player motion" % startup_step)
		get_tree().quit(1)
	# Reset must finish before observers such as the camera receive the signal.
	skier._bail()
	skier.crash_context.set_stage(CrashContext.Stage.REST)
	skier.crash_context.elapsed = 2.0
	for index: int in 30:
		skier.crash_context.advance(1.0 / 60.0)
		skier._update_animation(1.0 / 60.0)
	skier.grab_release_time = 0.4
	skier.grab_amount = 1.0
	skier.grab_tweak = Vector2.ONE
	skier.gesture_strength = 1.0
	skier.trick_command.grab_pose = TrickController.GrabPose.SAFETY_LEFT
	var signal_pose: Array[Vector3] = []
	skier.respawn_applied.connect(func(_value: Transform3D) -> void: signal_pose.assign(_visible_pose(skier)), CONNECT_ONE_SHOT)
	skier.respawn_at(spawn)
	var reset_gap := _pose_distance(initial_pose, signal_pose)
	if reset_gap > 0.01:
		push_error("CAMERA_RUNTIME_STABILITY_FAIL: respawn exposed %.3f m of stale crash pose to observers" % reset_gap)
		get_tree().quit(1)
	if skier.grab_release_time > 0.0 or skier.grab_amount > 0.0 or skier.grab_tweak != Vector2.ZERO or skier.gesture_strength > 0.0 or skier.trick_command.grab_pose != TrickController.GrabPose.NONE:
		push_error("CAMERA_RUNTIME_STABILITY_FAIL: respawn retained grab/input state")
		get_tree().quit(1)
	var camera_gap := initial_camera.origin.distance_to(camera.global_position)
	var camera_angle := initial_camera.basis.get_rotation_quaternion().angle_to(camera.global_basis.get_rotation_quaternion())
	if camera_gap > 0.01 or camera_angle > deg_to_rad(0.5):
		push_error("CAMERA_RUNTIME_STABILITY_FAIL: identical spawn reset changed camera by %.3f m / %.2f degrees" % [camera_gap, rad_to_deg(camera_angle)])
		get_tree().quit(1)
	print("SPAWN_RESET_MEASURE startup_step=%.3f reset_pose_gap=%.3f camera_gap=%.3f camera_angle=%.2f" % [startup_step, reset_gap, camera_gap, rad_to_deg(camera_angle)])

func _visible_pose(skier: SkierController) -> Array[Vector3]:
	var rig := skier.animation_controller
	var result: Array[Vector3] = []
	for point: Vector3 in rig.rig_adapter.landmarks().values():
		result.append(skier.to_local(point))
	for joint: Node3D in [rig.left_ski, rig.right_ski, rig.left_pole, rig.right_pole]:
		result.append(skier.to_local(joint.global_position))
		result.append(skier.to_local(joint.to_global(Vector3.FORWARD)))
	return result

func _pose_distance(first: Array[Vector3], second: Array[Vector3]) -> float:
	var maximum := 0.0
	for index: int in first.size():
		maximum = maxf(maximum, first[index].distance_to(second[index]))
	return maximum

func _physics_process(_delta: float) -> void:
	frame += 1
	var skier := resort.get_node("Skier") as SkierController
	var camera := resort.get_node("CameraRig") as SkiCameraController
	var snapshot := camera.debug_snapshot()
	var yaw := float(snapshot.get("actual_yaw_degrees", 0.0))
	var yaw_step := absf(rad_to_deg(angle_difference(deg_to_rad(previous_yaw), deg_to_rad(yaw))))
	max_yaw_step = maxf(max_yaw_step, yaw_step)
	if str(snapshot.get("state", "")) in ["GROUND", "RAIL"]:
		var travel := skier.velocity.slide(Vector3.UP)
		if travel.length_squared() < 0.001:
			travel = (-skier.global_basis.z).slide(Vector3.UP)
		if travel.length_squared() > 0.001:
			travel = travel.normalized()
			var planar_offset := (camera.global_position - skier.global_position).slide(Vector3.UP)
			var lateral_offset := (planar_offset - travel * planar_offset.dot(travel)).length()
			max_ground_lateral_offset = maxf(max_ground_lateral_offset, lateral_offset)
			if lateral_offset > MAX_GROUND_LATERAL_OFFSET:
				push_error(
					"CAMERA_RUNTIME_STABILITY_FAIL: ground camera drifted %.2f m laterally from the travel line at frame %d"
					% [lateral_offset, frame]
				)
				AudioManager.shutdown_audio()
				get_tree().quit(1)
				return
	if yaw_step > MAX_YAW_STEP_DEGREES:
		push_error(
			"CAMERA_RUNTIME_STABILITY_FAIL: yaw jumped %.2f degrees in one physics frame at frame %d (state=%s)"
			% [yaw_step, frame, snapshot.get("state", "unknown")]
		)
		AudioManager.shutdown_audio()
		get_tree().quit(1)
		return
	previous_yaw = yaw

	if frame >= MAX_FRAMES:
		print(
			"CAMERA_RUNTIME_STABILITY_PASS: max yaw step %.2f degrees, max ground lateral offset %.2f m"
			% [max_yaw_step, max_ground_lateral_offset]
		)
		AudioManager.shutdown_audio()
		get_tree().quit(0)
