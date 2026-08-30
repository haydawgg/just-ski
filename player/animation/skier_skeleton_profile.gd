class_name SkierSkeletonProfile
extends Resource

@export var body_scene: PackedScene
@export var model_transform := Transform3D.IDENTITY
@export var require_skinned_mesh := true
@export var pose_translation_scale := 1.0
@export var head_landmark_offset := Vector3(0.0, 0.22, 0.0)
@export var bone_names: Dictionary = {
	&"pelvis": &"Hips",
	&"spine": &"Spine",
	&"chest": &"Chest",
	&"head": &"Head",
	&"left_hip": &"LeftUpperLeg",
	&"right_hip": &"RightUpperLeg",
	&"left_knee": &"LeftLowerLeg",
	&"right_knee": &"RightLowerLeg",
	&"left_boot": &"LeftFoot",
	&"right_boot": &"RightFoot",
	&"left_shoulder": &"LeftUpperArm",
	&"right_shoulder": &"RightUpperArm",
	&"left_elbow": &"LeftLowerArm",
	&"right_elbow": &"RightLowerArm",
	&"left_hand": &"LeftHand",
	&"right_hand": &"RightHand",
}
@export var neutral_pose_rotations: Dictionary = {}
@export var axis_corrections: Dictionary = {}
@export var left_boot_offset := Transform3D.IDENTITY
@export var right_boot_offset := Transform3D.IDENTITY
@export var left_pole_offset := Transform3D.IDENTITY
@export var right_pole_offset := Transform3D.IDENTITY

func required_semantics() -> Array[StringName]:
	return [
		&"pelvis", &"spine", &"chest", &"head",
		&"left_hip", &"right_hip", &"left_knee", &"right_knee", &"left_boot", &"right_boot",
		&"left_shoulder", &"right_shoulder", &"left_elbow", &"right_elbow", &"left_hand", &"right_hand",
	]
