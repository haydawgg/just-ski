class_name GrabAnimationDefinition
extends Resource

enum Hand { NONE, LEFT, RIGHT, BOTH }
enum Ski { NONE, LEFT, RIGHT, BOTH }
enum Target { NONE, BINDING_OUTSIDE, BINDING_INSIDE, NOSE, TAIL }

@export var pose_id: int = 0
@export var display_name: String = ""
@export var hand: Hand = Hand.NONE
@export var target_ski: Ski = Ski.NONE
@export var target: Target = Target.NONE
@export var style_only: bool = false
@export_range(0.0, 1.0) var body_compactness: float = 0.65
@export var minimum_air_time: float = 0.08
@export var contact_acquire_distance: float = 0.64
@export var contact_maintain_distance: float = 0.72
@export var reach_response_scale: float = 1.0
@export var pelvis_offset: Vector3 = Vector3.ZERO
@export var pelvis_rotation: Vector3 = Vector3.ZERO
@export var spine_rotation: Vector3 = Vector3.ZERO
@export var chest_rotation: Vector3 = Vector3.ZERO
@export var left_hip_rotation: Vector3 = Vector3.ZERO
@export var right_hip_rotation: Vector3 = Vector3.ZERO
@export var left_knee_rotation: Vector3 = Vector3.ZERO
@export var right_knee_rotation: Vector3 = Vector3.ZERO
@export var left_ski_rotation: Vector3 = Vector3.ZERO
@export var right_ski_rotation: Vector3 = Vector3.ZERO
@export var left_shoulder_rotation: Vector3 = Vector3.ZERO
@export var right_shoulder_rotation: Vector3 = Vector3.ZERO
@export var left_elbow_rotation: Vector3 = Vector3.ZERO
@export var right_elbow_rotation: Vector3 = Vector3.ZERO
