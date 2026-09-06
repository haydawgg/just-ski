class_name SkierPoseDriver
extends Node3D

const REST_POSITIONS := {
	&"balance_root": Vector3.ZERO,
	&"pelvis": Vector3(0.0, 0.96, 0.0),
	&"spine": Vector3(0.0, 0.14, 0.0),
	&"chest": Vector3(0.0, 0.42, 0.0),
	&"head": Vector3(0.0, 0.38, 0.0),
	&"left_hip": Vector3(-0.27, -0.04, 0.0),
	&"right_hip": Vector3(0.27, -0.04, 0.0),
	&"left_knee": Vector3(0.0, -0.52, 0.0),
	&"right_knee": Vector3(0.0, -0.52, 0.0),
	&"left_boot": Vector3(0.0, -0.49, -0.03),
	&"right_boot": Vector3(0.0, -0.49, -0.03),
	&"left_ski": Vector3(0.0, -0.12, -0.08),
	&"right_ski": Vector3(0.0, -0.12, -0.08),
	&"left_shoulder": Vector3(-0.4, 0.24, 0.0),
	&"right_shoulder": Vector3(0.4, 0.24, 0.0),
	&"left_elbow": Vector3(0.0, -0.42, 0.0),
	&"right_elbow": Vector3(0.0, -0.42, 0.0),
	&"left_hand": Vector3(0.0, -0.37, 0.0),
	&"right_hand": Vector3(0.0, -0.37, 0.0),
	&"left_pole": Vector3.ZERO,
	&"right_pole": Vector3.ZERO,
}
const GRAB_TAIL_OFFSET := Vector3(0.0, 0.04, 0.20)

var joints: Dictionary = {}
var grab_targets: Dictionary = {}
var pole_tips: Dictionary = {}

func build() -> void:
	if not joints.is_empty():
		return
	var balance_root := _joint(&"balance_root", "BalanceRoot", self)
	var pelvis := _joint(&"pelvis", "Pelvis", balance_root)
	var spine := _joint(&"spine", "Spine", pelvis)
	var chest := _joint(&"chest", "Chest", spine)
	_joint(&"head", "Head", chest)
	var left_hip := _joint(&"left_hip", "LeftHip", pelvis)
	var right_hip := _joint(&"right_hip", "RightHip", pelvis)
	var left_knee := _joint(&"left_knee", "LeftKnee", left_hip)
	var right_knee := _joint(&"right_knee", "RightKnee", right_hip)
	var left_boot := _joint(&"left_boot", "LeftBoot", left_knee)
	var right_boot := _joint(&"right_boot", "RightBoot", right_knee)
	var left_ski := _joint(&"left_ski", "LeftSki", left_boot)
	var right_ski := _joint(&"right_ski", "RightSki", right_boot)
	_build_ski_targets(left_ski, "left", -1.0)
	_build_ski_targets(right_ski, "right", 1.0)
	var left_shoulder := _joint(&"left_shoulder", "LeftShoulder", chest)
	var right_shoulder := _joint(&"right_shoulder", "RightShoulder", chest)
	var left_elbow := _joint(&"left_elbow", "LeftElbow", left_shoulder)
	var right_elbow := _joint(&"right_elbow", "RightElbow", right_shoulder)
	var left_hand := _joint(&"left_hand", "LeftHand", left_elbow)
	var right_hand := _joint(&"right_hand", "RightHand", right_elbow)
	var left_pole := _joint(&"left_pole", "LeftPole", left_hand)
	var right_pole := _joint(&"right_pole", "RightPole", right_hand)
	pole_tips[&"left"] = _marker("LeftPoleTip", left_pole, Vector3(0.0, -1.185, 0.0))
	pole_tips[&"right"] = _marker("RightPoleTip", right_pole, Vector3(0.0, -1.185, 0.0))

func joint(semantic: StringName) -> Node3D:
	return joints.get(semantic) as Node3D

func rest_position(semantic: StringName) -> Vector3:
	return REST_POSITIONS.get(semantic, Vector3.ZERO) as Vector3

func grab_target(side: StringName, target: StringName) -> Node3D:
	return grab_targets.get(StringName("%s_%s" % [side, target])) as Node3D

func canonical_landmarks() -> Dictionary:
	return {
		"head": joint(&"head").to_global(Vector3(0.0, 0.29, 0.0)),
		"pelvis": joint(&"pelvis").global_position,
		"left_knee": joint(&"left_knee").global_position,
		"right_knee": joint(&"right_knee").global_position,
		"left_boot": joint(&"left_boot").global_position,
		"right_boot": joint(&"right_boot").global_position,
		"left_ski_nose": grab_target(&"left", &"nose").global_position,
		"right_ski_nose": grab_target(&"right", &"nose").global_position,
		"left_ski_tail": grab_target(&"left", &"tail").global_position,
		"right_ski_tail": grab_target(&"right", &"tail").global_position,
		"left_hand": joint(&"left_hand").global_position,
		"right_hand": joint(&"right_hand").global_position,
		"left_pole_tip": (pole_tips[&"left"] as Node3D).global_position,
		"right_pole_tip": (pole_tips[&"right"] as Node3D).global_position,
	}

func _joint(semantic: StringName, node_name: String, parent: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = rest_position(semantic)
	parent.add_child(node)
	joints[semantic] = node
	return node

func _build_ski_targets(ski: Node3D, side: String, side_sign: float) -> void:
	var outside_x := 0.075 * side_sign
	var inside_x := -outside_x
	grab_targets[StringName(side + "_binding_outside")] = _marker(side.capitalize() + "GrabBindingOutside", ski, Vector3(outside_x, 0.04, 0.05))
	grab_targets[StringName(side + "_binding_inside")] = _marker(side.capitalize() + "GrabBindingInside", ski, Vector3(inside_x, 0.04, 0.02))
	grab_targets[StringName(side + "_nose")] = _marker(side.capitalize() + "GrabNose", ski, Vector3(0.0, 0.04, -0.72))
	# Keep the tail contact just inside the upturned tail so the measured
	# production arm envelope can hold it after the ski pivot follows the animated
	# boot. The old +0.42m point sat too far behind the boot during a deep tail
	# grab and made the hand visibly lose contact.
	grab_targets[StringName(side + "_tail")] = _marker(side.capitalize() + "GrabTail", ski, GRAB_TAIL_OFFSET)

func _marker(node_name: String, parent: Node3D, local_position: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.name = node_name
	marker.position = local_position
	parent.add_child(marker)
	return marker
