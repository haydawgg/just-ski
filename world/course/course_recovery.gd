class_name CourseRecovery
extends Node

signal recovery_started

@export var minimum_y := -24.0
@export var minimum_z := -225.0
@export var maximum_z := 175.0
@export var maximum_lateral_distance := 72.0
@export var recovery_delay := 0.45

var target: CharacterBody3D
var outside_time := 0.0
var recovering := false

func set_target(value: CharacterBody3D) -> void:
	target = value
	outside_time = 0.0
	recovering = false

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var position := target.global_position
	var invalid := (
		not position.is_finite()
		or position.y < minimum_y
		or position.z < minimum_z
		or position.z > maximum_z
		or absf(position.x) > maximum_lateral_distance
	)
	if not invalid:
		outside_time = 0.0
		recovering = false
		return
	outside_time += delta
	if outside_time < recovery_delay or recovering:
		return
	recovering = true
	recovery_started.emit()
	SessionManager.request_respawn()
	outside_time = 0.0

