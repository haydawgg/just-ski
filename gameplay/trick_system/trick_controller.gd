class_name TrickController
extends Node

signal trick_changed(text: String)
signal trick_landed(text: String, points: int, quality: float)

enum GrabPose {
	NONE,
	SAFETY_LEFT,
	SAFETY_RIGHT,
	MUTE_LEFT,
	MUTE_RIGHT,
	JAPAN_LEFT,
	JAPAN_RIGHT,
	TAIL,
	NOSE,
	DOUBLE,
	SPREAD_EAGLE,
	DAFFY,
}

const GRAB_NAMES: Array[String] = [
	"", "Safety Grab Left", "Safety Grab Right", "Mute Grab Left", "Mute Grab Right",
	"Japan Grab Left", "Japan Grab Right", "Tail Grab", "Nose Grab", "Double Grab",
	"Spread Eagle", "Daffy",
]

var active := false
var accumulated_rotation := Vector3.ZERO
var grab_name := ""
var grab_pose := GrabPose.NONE
var grind_seconds := 0.0
var switch_takeoff := false
var air_seconds := 0.0
var grab_seconds := 0.0
var tweak_integral := 0.0
var dominant_kind := TrickCommand.Kind.NONE
var rail_pose := 0
var had_trick_intent := false

func begin_air(is_switch: bool, takeoff_kind: int = TrickCommand.Kind.POP) -> void:
	active = true
	accumulated_rotation = Vector3.ZERO
	grab_name = ""
	grab_pose = GrabPose.NONE
	grind_seconds = 0.0
	switch_takeoff = is_switch
	air_seconds = 0.0
	grab_seconds = 0.0
	tweak_integral = 0.0
	dominant_kind = takeoff_kind
	rail_pose = 0
	had_trick_intent = takeoff_kind != TrickCommand.Kind.NONE

func update_air(local_angular_velocity: Vector3, delta: float, command: TrickCommand = null) -> void:
	if not active:
		return
	air_seconds += delta
	accumulated_rotation += local_angular_velocity * delta
	if command != null:
		if command.committed and command.kind not in [TrickCommand.Kind.NONE, TrickCommand.Kind.POP]:
			dominant_kind = command.kind
			had_trick_intent = true
		grab_pose = command.grab_pose
		if grab_pose != GrabPose.NONE:
			grab_seconds += delta * command.grab_amount
			tweak_integral += command.grab_tweak.length() * delta
			had_trick_intent = true
	else:
		grab_pose = _resolve_legacy_grab_pose()
	# The live pose can return to neutral before touchdown, but the completed
	# trick still owns any grab that was held during the air. Keep the last
	# non-neutral name for scoring and the landing callout.
	if grab_pose != GrabPose.NONE:
		grab_name = GRAB_NAMES[grab_pose]
	trick_changed.emit(current_name())

func update_grind(delta: float, selected_pose: int = 0) -> void:
	active = true
	grind_seconds += delta
	rail_pose = selected_pose
	had_trick_intent = true
	var rail_name := "50-50" if rail_pose == 0 else ("Boardslide Left" if rail_pose < 0 else "Boardslide Right")
	trick_changed.emit("%s %.1fs" % [rail_name, grind_seconds])

func land(quality: float, switch_landing: bool, link_bonus: int = 0) -> void:
	if not active:
		return
	var name := current_name()
	var spin_degrees := _spin_degrees()
	var flip_degrees := _flip_degrees()
	var cork_degrees := _cork_degrees()
	var motion_points := 0
	if dominant_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
		motion_points = cork_degrees * 3
	else:
		motion_points = spin_degrees * 2 + int(float(flip_degrees) / 360.0 * 500.0)
	var points: int = motion_points + int(grind_seconds * 300.0)
	if not grab_name.is_empty():
		points += 150 + int(grab_seconds * 120.0) + int(tweak_integral * 80.0)
	if switch_landing != switch_takeoff:
		name += " to Switch"
		points += 120
	if link_bonus > 0:
		name = "Line Link + " + name
		points += 200 * link_bonus
	if points <= 0 and dominant_kind == TrickCommand.Kind.POP and air_seconds >= 0.15:
		points = 50
	if points <= 0 and grind_seconds < 0.08:
		reset()
		return
	if points <= 0 and grind_seconds >= 0.08:
		points = int(grind_seconds * 300.0)
	points = int(points * clampf(quality, 0.2, 1.0))
	trick_landed.emit(name, points, quality)
	reset()

func current_name() -> String:
	var parts: Array[String] = []
	var spin_degrees := _spin_degrees()
	var flip_degrees := _flip_degrees()
	var cork_degrees := _cork_degrees()
	if grind_seconds > 0.0:
		parts.append("50-50" if rail_pose == 0 else ("Boardslide Left" if rail_pose < 0 else "Boardslide Right"))
	if dominant_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT] and cork_degrees >= 180:
		parts.append("%s Cork %d" % ["Left" if dominant_kind == TrickCommand.Kind.CORK_LEFT else "Right", cork_degrees])
	else:
		if spin_degrees >= 180:
			parts.append("%s %d" % ["Left" if accumulated_rotation.y < 0.0 else "Right", spin_degrees])
		if flip_degrees >= 360:
			parts.append("%s%s" % ["Frontflip" if accumulated_rotation.x > 0.0 else "Backflip", " x%d" % int(flip_degrees / 360) if flip_degrees >= 720 else ""])
	if not grab_name.is_empty():
		parts.append(grab_name)
	return "Straight Air" if parts.is_empty() else " + ".join(parts)

func reset() -> void:
	active = false
	accumulated_rotation = Vector3.ZERO
	grab_name = ""
	grab_pose = GrabPose.NONE
	grind_seconds = 0.0
	air_seconds = 0.0
	grab_seconds = 0.0
	tweak_integral = 0.0
	dominant_kind = TrickCommand.Kind.NONE
	rail_pose = 0
	had_trick_intent = false
	trick_changed.emit("")

func _spin_degrees() -> int:
	if absf(accumulated_rotation.y) < deg_to_rad(135.0):
		return 0
	return int(round(absf(accumulated_rotation.y) / PI) * 180.0)

func _flip_degrees() -> int:
	if absf(accumulated_rotation.x) < deg_to_rad(270.0):
		return 0
	return int(round(absf(accumulated_rotation.x) / TAU) * 360.0)

func _cork_degrees() -> int:
	var amount := maxf(absf(accumulated_rotation.y), absf(accumulated_rotation.z))
	if amount < deg_to_rad(135.0):
		return 0
	return int(round(amount / PI) * 180.0)

func _resolve_legacy_grab_pose() -> GrabPose:
	var left := Input.is_action_pressed("grab_left")
	var right := Input.is_action_pressed("grab_right")
	var style := InputManager.vector(&"trick_left", &"trick_right", &"trick_up", &"trick_down")
	if left and right:
		if style.y < -0.45:
			return GrabPose.SPREAD_EAGLE
		if style.y > 0.45:
			return GrabPose.DAFFY
		return GrabPose.DOUBLE
	if left:
		if style.x > 0.45:
			return GrabPose.MUTE_LEFT
		if style.y < -0.45:
			return GrabPose.JAPAN_LEFT
		if style.y > 0.45:
			return GrabPose.TAIL
		return GrabPose.SAFETY_LEFT
	if right:
		if style.x < -0.45:
			return GrabPose.MUTE_RIGHT
		if style.y < -0.45:
			return GrabPose.JAPAN_RIGHT
		if style.y > 0.45:
			return GrabPose.NOSE
		return GrabPose.SAFETY_RIGHT
	return GrabPose.NONE
