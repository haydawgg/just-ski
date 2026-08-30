class_name SkierRigAdapter
extends Node3D

var driver: SkierPoseDriver
var error_message := ""

func configure(value: SkierPoseDriver, _skeleton_profile: Resource = null) -> bool:
	driver = value
	error_message = ""
	return driver != null

func sync_pose(_delta: float) -> void:
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

func adapter_name() -> String:
	return "base"

func validation_error() -> String:
	return error_message
