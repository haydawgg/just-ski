class_name GrabAnimationDefinition
extends "res://player/animation/skier_pose_shape_definition.gd"

enum Hand { NONE, LEFT, RIGHT, BOTH }
enum Ski { NONE, LEFT, RIGHT, BOTH }
enum Target { NONE, BINDING_OUTSIDE, BINDING_INSIDE, NOSE, TAIL }

@export var hand: Hand = Hand.NONE
@export var target_ski: Ski = Ski.NONE
@export var target: Target = Target.NONE
@export var minimum_air_time: float = 0.08
@export var contact_acquire_distance: float = 0.18
@export var contact_maintain_distance: float = 0.12
@export var reach_response_scale: float = 1.0
@export_range(0.0, 1.0) var clavicle_assist_scale: float = 1.0
@export_range(0.0, 4.0) var upper_spine_assist_scale: float = 1.0
@export_range(0.25, 3.0) var contact_response_scale: float = 1.0
