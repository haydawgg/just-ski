class_name SkiCameraController
extends Node3D

@export var follow_distance := 7.5
@export var follow_height := 3.0
@export var spring_strength := 10.0
@export var damping := 6.5
@export var base_fov := 72.0
@export var speed_fov_gain := 16.0

var target: CharacterBody3D
var camera: Camera3D
var spring_velocity := Vector3.ZERO
var look_velocity := Vector3.ZERO

func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = base_fov
	camera.near = 0.08
	add_child(camera)

func set_target(value: CharacterBody3D) -> void:
	target = value
	reset_immediate()

func reset_immediate() -> void:
	if target == null:
		return
	var forward := -target.global_basis.z
	global_position = target.global_position - forward * follow_distance + Vector3.UP * follow_height
	spring_velocity = Vector3.ZERO
	look_at(target.global_position + forward * 4.0 + Vector3.UP, Vector3.UP)

func _process(delta: float) -> void:
	if target == null:
		return
	var speed := target.velocity.length()
	var travel := target.velocity.slide(Vector3.UP).normalized()
	if travel.length_squared() < 0.05:
		travel = -target.global_basis.z
	var distance := follow_distance + clampf(speed * 0.065, 0.0, 3.0)
	var desired := target.global_position - travel * distance + Vector3.UP * (follow_height + clampf(speed * 0.018, 0.0, 0.8))
	var acceleration := (desired - global_position) * spring_strength - spring_velocity * damping
	spring_velocity += acceleration * delta
	global_position += spring_velocity * delta
	global_position = _avoid_collision(target.global_position + Vector3.UP, global_position)
	var look_ahead := clampf(speed * 0.22, 3.0, 11.0)
	var look_target := target.global_position + travel * look_ahead + Vector3.UP * 0.8
	var current_forward := -global_basis.z
	var desired_forward := global_position.direction_to(look_target)
	var blended := current_forward.slerp(desired_forward, 1.0 - exp(-7.0 * delta)).normalized()
	global_basis = Basis.looking_at(blended, Vector3.UP)
	camera.fov = lerpf(camera.fov, base_fov + clampf(speed / 45.0, 0.0, 1.0) * speed_fov_gain, 1.0 - exp(-4.0 * delta))

func _avoid_collision(from: Vector3, desired: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, desired, 0b101)
	query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	return hit.position + hit.normal * 0.35
