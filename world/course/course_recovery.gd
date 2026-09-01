class_name CourseRecovery
extends Node

## Course recovery is an explicit lifecycle rather than a one-frame teleport.
## Keep the reason on the signal so crash/replay diagnostics can distinguish a
## valid out-of-bounds recovery from an invalid transform.
signal recovery_started(reason: String)
signal recovery_respawned(reason: String, spawn_transform: Transform3D)
signal recovery_completed(reason: String, spawn_transform: Transform3D)

enum RecoveryReason { OUT_OF_BOUNDS, INVALID_POSITION }

@export var minimum_y := -24.0
@export var minimum_z := -225.0
@export var maximum_z := 175.0
@export var maximum_lateral_distance := 72.0
@export var recovery_delay := 0.45
@export var fade_out_duration := 0.12
@export var fade_in_duration := 0.18

var target: CharacterBody3D
var outside_time := 0.0
var recovering := false
var recovery_elapsed := 0.0
var respawn_issued := false
var recovery_count := 0
var last_recovery_reason := ""
var last_respawn_transform := Transform3D.IDENTITY

var recovery_in_progress: bool:
	get:
		return recovering

func set_target(value: CharacterBody3D) -> void:
	target = value
	outside_time = 0.0
	recovering = false
	recovery_elapsed = 0.0
	respawn_issued = false
	if target != null and target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", false)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	if recovering:
		recovery_elapsed += delta
		if not respawn_issued and recovery_elapsed >= maxf(fade_out_duration, 0.0):
			respawn_issued = true
			last_respawn_transform = SessionManager.marker if SessionManager.has_marker else SessionManager.default_spawn
			SessionManager.request_respawn()
			recovery_respawned.emit(last_recovery_reason, last_respawn_transform)
		if respawn_issued and recovery_elapsed >= maxf(fade_out_duration, 0.0) + maxf(fade_in_duration, 0.0):
			_finish_recovery()
		return
	var position := target.global_position
	var invalid_transform := not position.is_finite()
	var invalid_bounds := (
		position.y < minimum_y
		or position.z < minimum_z
		or position.z > maximum_z
		or absf(position.x) > maximum_lateral_distance
	)
	if not invalid_transform and not invalid_bounds:
		outside_time = 0.0
		return
	outside_time += delta
	var required_delay := 0.0 if invalid_transform else maxf(recovery_delay, 0.0)
	if outside_time < required_delay:
		return
	recovering = true
	recovery_elapsed = 0.0
	respawn_issued = false
	recovery_count += 1
	last_recovery_reason = RecoveryReason.keys()[RecoveryReason.INVALID_POSITION if invalid_transform else RecoveryReason.OUT_OF_BOUNDS]
	if target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", true)
	recovery_started.emit(last_recovery_reason)
	outside_time = 0.0

func _finish_recovery() -> void:
	if not recovering:
		return
	recovering = false
	recovery_elapsed = 0.0
	respawn_issued = false
	if target != null and target.has_method("set_recovery_frozen"):
		target.call("set_recovery_frozen", false)
	recovery_completed.emit(last_recovery_reason, last_respawn_transform)
