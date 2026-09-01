class_name CameraFramingSolver
extends RefCounted

## Stateful airborne vertical framing. The camera coordinator supplies the
## current target and profile values; this module owns the anchor and bounded
## dead-zone response.

var air_vertical_dead_zone := 0.5
var air_vertical_recovery_zone := 1.15
var air_vertical_anchor_response := 3.4
var air_vertical_edge_response := 9.0
var air_vertical_hard_recovery_response := 20.0

var _air_anchor_height := 0.0
var _air_anchor_valid := false

func configure(
	dead_zone: float,
	recovery_zone: float,
	anchor_response: float,
	edge_response: float,
	hard_recovery_response: float
) -> void:
	air_vertical_dead_zone = dead_zone
	air_vertical_recovery_zone = recovery_zone
	air_vertical_anchor_response = anchor_response
	air_vertical_edge_response = edge_response
	air_vertical_hard_recovery_response = hard_recovery_response

func reset(anchor_height: float, airborne: bool) -> void:
	_air_anchor_height = anchor_height
	_air_anchor_valid = airborne

func clear() -> void:
	_air_anchor_valid = false

func step_air(player_position: Vector3, up: Vector3, delta: float, air_entry_time: float) -> Vector3:
	var safe_up := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var player_height := player_position.dot(safe_up)
	if not _air_anchor_valid:
		_air_anchor_height = player_height
		_air_anchor_valid = true
	var height_delta := player_height - _air_anchor_height
	var target_height := player_height
	if absf(height_delta) <= air_vertical_dead_zone:
		target_height = _air_anchor_height
	else:
		target_height = player_height - signf(height_delta) * air_vertical_dead_zone
	var displacement := absf(height_delta)
	var recovery_span := maxf(air_vertical_recovery_zone - air_vertical_dead_zone, 0.001)
	var edge_weight := smoothstep(
		0.0,
		1.0,
		clampf((displacement - air_vertical_dead_zone) / recovery_span, 0.0, 1.0)
	)
	var response := lerpf(air_vertical_anchor_response, air_vertical_edge_response, edge_weight)
	if displacement > air_vertical_recovery_zone:
		var hard_span := maxf(air_vertical_recovery_zone * 0.5, 0.001)
		var hard_weight := smoothstep(0.0, 1.0, clampf((displacement - air_vertical_recovery_zone) / hard_span, 0.0, 1.0))
		var capped_hard_response := minf(air_vertical_hard_recovery_response, 12.0)
		response = lerpf(air_vertical_edge_response, capped_hard_response, hard_weight)
	if air_entry_time >= 0.0 and air_entry_time < 0.18:
		response *= 0.35
	_air_anchor_height = lerpf(_air_anchor_height, target_height, 1.0 - exp(-response * maxf(delta, 0.0)))
	return player_position + safe_up * (_air_anchor_height - player_height)
