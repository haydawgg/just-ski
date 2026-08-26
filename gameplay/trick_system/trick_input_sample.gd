class_name TrickInputSample
extends RefCounted

var right_stick := Vector2.ZERO
var left_stick := Vector2.ZERO
var left_trigger := 0.0
var right_trigger := 0.0
var keyboard_pop_pressed := false
var keyboard_pop_released := false

func reset() -> void:
	right_stick = Vector2.ZERO
	left_stick = Vector2.ZERO
	left_trigger = 0.0
	right_trigger = 0.0
	keyboard_pop_pressed = false
	keyboard_pop_released = false
