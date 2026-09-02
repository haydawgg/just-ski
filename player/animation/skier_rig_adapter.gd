class_name SkierRigAdapter
extends Node3D

var driver: SkierPoseDriver
var error_message := ""

func configure(value: SkierPoseDriver, _skeleton_profile: Resource = null) -> bool:
	driver = value
	error_message = ""
	return driver != null

func sync_pose(_delta: float, _grab_requests: Array[SkierGrabReachRequest] = []) -> void:
	pass

func landmarks() -> Dictionary:
	return driver.canonical_landmarks() if driver != null else {}

func grab_target(side: StringName, target: StringName) -> Node3D:
	return driver.grab_target(side, target) if driver != null else null

func arm_lengths(_side: StringName) -> Vector2:
	if driver == null:
		return Vector2.ZERO
	return Vector2(
		driver.rest_position(&"left_elbow").length(),
		driver.rest_position(&"left_hand").length()
	)

## Returns true when this adapter owns the final visual hand-to-ski solve. The
## canonical controller keeps its existing arm solve for adapters that return
## false, preserving the primitive fallback behavior.
func owns_grab_reach() -> bool:
	return false

func grab_contact_point(side: StringName) -> Vector3:
	if driver == null:
		return Vector3.ZERO
	var hand := driver.joint(StringName("%s_hand" % side))
	return hand.global_position if hand != null else Vector3.ZERO

func grab_reach_error(_side: StringName) -> float:
	return 0.0

func grab_target_world(_side: StringName) -> Vector3:
	return Vector3.ZERO

func grab_debug_snapshot() -> Dictionary:
	return {}

func adapter_name() -> String:
	return "base"

func validation_error() -> String:
	return error_message
