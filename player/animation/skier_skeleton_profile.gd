class_name SkierSkeletonProfile
extends Resource

@export var body_scene: PackedScene
@export var model_transform := Transform3D.IDENTITY
@export var require_skinned_mesh := true
@export var pose_translation_scale := 1.0
@export var head_landmark_offset := Vector3(0.0, 0.29, 0.0)
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
## Optional helper bones used by the production reach solver. Profiles for rigs
## without these helpers remain valid and fall back to the mapped arm chain.
@export var helper_bone_names: Dictionary = {
	&"upper_spine": &"",
	&"left_clavicle": &"",
	&"right_clavicle": &"",
}
## Local offsets from each hand bone origin to the visible palm contact point.
@export var hand_contact_offsets: Dictionary = {
	&"left": Vector3.ZERO,
	&"right": Vector3.ZERO,
}
## Local hand orientation corrections applied when the palm follows a ski marker.
@export var hand_wrist_corrections: Dictionary = {}
## Reach assistance is intentionally bounded and remains rig calibration, not
## gameplay or trick tuning.
@export_range(0.0, 1.0) var upper_spine_reach_assist: float = 0.16
@export_range(0.0, 3.14159) var upper_spine_reach_limit: float = 0.28
@export_range(0.0, 1.0) var clavicle_reach_assist: float = 0.9
@export_range(0.0, 3.14159) var clavicle_reach_limit: float = 0.7
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

func helper_semantics() -> Array[StringName]:
	return [&"upper_spine", &"left_clavicle", &"right_clavicle"]
