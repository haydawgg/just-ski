class_name CrashContext
extends RefCounted

enum Reason {
	NONE,
	LANDING_UPRIGHT,
	LANDING_IMPACT,
	LANDING_ANGULAR,
	FEATURE_IMPACT,
}

enum Source {
	NONE,
	LANDING,
	RAIL,
	OBSTACLE,
}

enum Stage {
	NONE,
	RELEASE,
	IMPACT,
	FALL,
	REST,
	RECOVERY,
}

var active := false
var reason: int = Reason.NONE
var source: int = Source.NONE
var source_state := -1
var stage: int = Stage.NONE
var incoming_velocity := Vector3.ZERO
var current_velocity := Vector3.ZERO
var impact_normal := Vector3.UP
var impact_speed := 0.0
var speed_loss := 0.0
var angular_speed := 0.0
var balance_error := 0.0
var rail_balance := 0.0
var lateral_bias := 0.0
var elapsed := 0.0
var stage_elapsed := 0.0
var rest_elapsed := 0.0
var rest_detected := false
var collision_collider := ""
var collision_asset_id := ""
var collision_layer := 0
var collision_normal := Vector3.UP
var collision_position := Vector3.ZERO

func begin(
	crash_reason: int,
	crash_source: int,
	crash_source_state: int,
	pre_impact_velocity: Vector3,
	post_impact_velocity: Vector3,
	normal: Vector3,
	normal_impact_speed: float,
	crash_angular_speed: float,
	crash_balance_error: float = 0.0,
	crash_rail_balance: float = 0.0,
	crash_lateral_bias: float = 0.0
) -> void:
	active = true
	reason = crash_reason
	source = crash_source
	source_state = crash_source_state
	stage = Stage.RELEASE
	incoming_velocity = pre_impact_velocity
	current_velocity = post_impact_velocity
	impact_normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	impact_speed = maxf(0.0, normal_impact_speed)
	speed_loss = maxf(0.0, pre_impact_velocity.length() - post_impact_velocity.length())
	angular_speed = maxf(0.0, crash_angular_speed)
	balance_error = clampf(crash_balance_error, 0.0, 1.0)
	rail_balance = clampf(crash_rail_balance, -1.35, 1.35)
	lateral_bias = clampf(crash_lateral_bias, -1.0, 1.0)
	elapsed = 0.0
	stage_elapsed = 0.0
	rest_elapsed = 0.0
	rest_detected = false
	collision_collider = ""
	collision_asset_id = ""
	collision_layer = 0
	collision_normal = Vector3.UP
	collision_position = Vector3.ZERO

func attach_collision_diagnostic(diagnostic: Dictionary) -> void:
	collision_collider = str(diagnostic.get("collider", ""))
	collision_asset_id = str(diagnostic.get("asset_id", ""))
	collision_layer = int(diagnostic.get("collider_layer", 0))
	collision_normal = diagnostic.get("normal", Vector3.UP) as Vector3
	collision_position = diagnostic.get("position", Vector3.ZERO) as Vector3

func reset() -> void:
	active = false
	reason = Reason.NONE
	source = Source.NONE
	source_state = -1
	stage = Stage.NONE
	incoming_velocity = Vector3.ZERO
	current_velocity = Vector3.ZERO
	impact_normal = Vector3.UP
	impact_speed = 0.0
	speed_loss = 0.0
	angular_speed = 0.0
	balance_error = 0.0
	rail_balance = 0.0
	lateral_bias = 0.0
	elapsed = 0.0
	stage_elapsed = 0.0
	rest_elapsed = 0.0
	rest_detected = false
	collision_collider = ""
	collision_asset_id = ""
	collision_layer = 0
	collision_normal = Vector3.UP
	collision_position = Vector3.ZERO

func advance(delta: float) -> void:
	var step := maxf(delta, 0.0)
	elapsed += step
	stage_elapsed += step

func set_stage(next_stage: int) -> void:
	if stage == next_stage:
		return
	stage = next_stage
	stage_elapsed = 0.0

func normalized_stage_progress(duration: float) -> float:
	return clampf(stage_elapsed / maxf(duration, 0.001), 0.0, 1.0)

func snapshot() -> Dictionary:
	return {
		"active": active,
		"reason": Reason.keys()[reason],
		"source": Source.keys()[source],
		"source_state": source_state,
		"stage": Stage.keys()[stage],
		"incoming_velocity": incoming_velocity,
		"current_velocity": current_velocity,
		"impact_normal": impact_normal,
		"impact_speed": impact_speed,
		"speed_loss": speed_loss,
		"angular_speed": angular_speed,
		"balance_error": balance_error,
		"rail_balance": rail_balance,
		"lateral_bias": lateral_bias,
		"elapsed": elapsed,
		"stage_elapsed": stage_elapsed,
		"rest_elapsed": rest_elapsed,
		"rest_detected": rest_detected,
		"collision_collider": collision_collider,
		"collision_asset_id": collision_asset_id,
		"collision_layer": collision_layer,
		"collision_normal": collision_normal,
		"collision_position": collision_position,
	}
