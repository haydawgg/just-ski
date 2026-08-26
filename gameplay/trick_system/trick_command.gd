class_name TrickCommand
extends RefCounted

enum Kind {
	NONE,
	POP,
	SPIN_LEFT,
	SPIN_RIGHT,
	FRONTFLIP,
	BACKFLIP,
	CORK_LEFT,
	CORK_RIGHT,
	RAIL_POP,
	RAIL_SLIDE_LEFT,
	RAIL_SLIDE_RIGHT,
}

enum PresentationPhase { NEUTRAL, SETUP, RELEASE, ROTATE, GRAB, OPEN, LANDING }

var kind := Kind.NONE
var phase := PresentationPhase.NEUTRAL
var pop_strength := 0.0
var rotation_impulse := Vector3.ZERO
var gesture_strength := 0.0
var grab_pose := 0
var grab_amount := 0.0
var grab_tweak := Vector2.ZERO
var left_trigger := 0.0
var right_trigger := 0.0
var committed := false

func reset() -> void:
	kind = Kind.NONE
	phase = PresentationPhase.NEUTRAL
	pop_strength = 0.0
	rotation_impulse = Vector3.ZERO
	gesture_strength = 0.0
	grab_pose = 0
	grab_amount = 0.0
	grab_tweak = Vector2.ZERO
	left_trigger = 0.0
	right_trigger = 0.0
	committed = false
