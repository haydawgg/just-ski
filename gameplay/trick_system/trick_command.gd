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
## Full takeoff budget and the portion released by this command. Gameplay keeps
## the persistent release state; the interpreter only authors the gesture curve.
var takeoff_rotation_impulse := Vector3.ZERO
var takeoff_release_impulse := Vector3.ZERO
var rotation_axis_local := Vector3.ZERO
var rotation_axis_weights := Vector3.ZERO
var gesture_strength := 0.0

# Takeoff gesture telemetry. These values describe the gesture that produced
# the command; they do not persist for the whole air. Persistent rotation state
# belongs to gameplay rather than this one-frame command object.
var setup_depth := 0.0
var setup_duration := 0.0
var release_speed := 0.0
var release_direction := Vector2.ZERO
var setup_quality := 0.0
var takeoff_rotation_committed := false

# Airborne rotation input manages the continuous axis committed at takeoff.
# It must not silently replace that physical intent.
## Signed projection onto the committed control direction. Positive compacts,
## negative opens/checks, and zero leaves natural momentum unchanged.
var air_control_projection := 0.0

var grab_pose := 0
var grab_amount := 0.0
var style_pose := 0
var style_amount := 0.0
var grab_tweak := Vector2.ZERO
var left_trigger := 0.0
var right_trigger := 0.0
var committed := false

func reset() -> void:
	kind = Kind.NONE
	phase = PresentationPhase.NEUTRAL
	pop_strength = 0.0
	rotation_impulse = Vector3.ZERO
	takeoff_rotation_impulse = Vector3.ZERO
	takeoff_release_impulse = Vector3.ZERO
	rotation_axis_local = Vector3.ZERO
	rotation_axis_weights = Vector3.ZERO
	gesture_strength = 0.0
	setup_depth = 0.0
	setup_duration = 0.0
	release_speed = 0.0
	release_direction = Vector2.ZERO
	setup_quality = 0.0
	takeoff_rotation_committed = false
	air_control_projection = 0.0
	grab_pose = 0
	grab_amount = 0.0
	style_pose = 0
	style_amount = 0.0
	grab_tweak = Vector2.ZERO
	left_trigger = 0.0
	right_trigger = 0.0
	committed = false
