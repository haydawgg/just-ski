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
	previous_yaw = float(camera.debug_snapshot().get("actual_yaw_degrees", 0.0))

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
