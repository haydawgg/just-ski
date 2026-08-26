class_name TrickController
extends Node

signal trick_changed(text: String)
signal trick_landed(text: String, points: int, quality: float)

var active := false
var accumulated_rotation := Vector3.ZERO
var grab_name := ""
var grind_seconds := 0.0
var switch_takeoff := false

func begin_air(is_switch: bool) -> void:
	active = true
	accumulated_rotation = Vector3.ZERO
	grab_name = ""
	grind_seconds = 0.0
	switch_takeoff = is_switch

func update_air(local_angular_velocity: Vector3, delta: float) -> void:
	if not active:
		return
	accumulated_rotation += local_angular_velocity * delta
	if Input.is_action_pressed("grab_left"):
		grab_name = "Left Grab"
	elif Input.is_action_pressed("grab_right"):
		grab_name = "Right Grab"
	trick_changed.emit(current_name())

func update_grind(delta: float) -> void:
	active = true
	grind_seconds += delta
	trick_changed.emit("Rail %.1fs" % grind_seconds)

func land(quality: float, switch_landing: bool) -> void:
	if not active:
		return
	var name := current_name()
	var degrees := int(round(absf(accumulated_rotation.y) / TAU * 360.0 / 180.0) * 180.0)
	var points: int = maxi(50, degrees * 2 + int(grind_seconds * 300.0))
	if not grab_name.is_empty():
		points += 150
	if switch_landing != switch_takeoff:
		name += " to Switch"
		points += 120
	points = int(points * clampf(quality, 0.2, 1.0))
	trick_landed.emit(name, points, quality)
	reset()

func current_name() -> String:
	var parts: Array[String] = []
	var spin_degrees := int(round(absf(accumulated_rotation.y) / TAU * 360.0 / 180.0) * 180.0)
	var flip_degrees := int(round(absf(accumulated_rotation.x) / TAU * 360.0 / 180.0) * 180.0)
	if grind_seconds > 0.0:
		parts.append("Rail")
	if spin_degrees >= 180:
		parts.append("%d" % spin_degrees)
	if flip_degrees >= 270:
		parts.append("Frontflip" if accumulated_rotation.x > 0.0 else "Backflip")
	if not grab_name.is_empty():
		parts.append(grab_name)
	return "Straight Air" if parts.is_empty() else " + ".join(parts)

func reset() -> void:
	active = false
	accumulated_rotation = Vector3.ZERO
	grab_name = ""
	grind_seconds = 0.0
	trick_changed.emit("")
