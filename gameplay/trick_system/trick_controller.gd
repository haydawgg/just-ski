class_name TrickController
extends Node

const MIN_STRAIGHT_AIR_PRESENTATION_TIME := 0.45
const MIN_GRAB_QUALIFY_TIME := 0.1
const MIN_GRIND_SECONDS := 0.08
const MAX_GRIND_SCORE_SECONDS := 4.0
const MAX_CREDITED_SPIN_DEGREES := 1080
const MAX_TWEAK_INTEGRAL := 5.0
const SPIN_STEP_DEGREES := 180.0
const FLIP_STEP_DEGREES := 360.0
const SPIN_MAX_UNDERROTATION_DEGREES := 25.0
const FLIP_MAX_UNDERROTATION_DEGREES := 45.0
const CLEAN_ROTATION_RESIDUAL_DEGREES := 25.0
const SKETCHY_ROTATION_RESIDUAL_DEGREES := 55.0

signal trick_changed(text: String)
signal trick_landed(text: String, points: int, quality: float, outcome: int)

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
}

enum StylePose { NONE, SPREAD_EAGLE, DAFFY, SHIFTY_LEFT, SHIFTY_RIGHT }

const GRAB_NAMES: Array[String] = [
	"", "Safety Grab Left", "Safety Grab Right", "Mute Grab Left", "Mute Grab Right",
	"Japan Grab Left", "Japan Grab Right", "Tail Grab", "Nose Grab", "Double Grab",
]

const STYLE_NAMES: Array[String] = ["", "Spread Eagle", "Daffy", "Shifty Left", "Shifty Right"]

var active := false
var accumulated_rotation := Vector3.ZERO
var grab_name := ""
var live_grab_name := ""
var grab_contact_seconds := 0.0
var grab_qualified := false
var grab_pose := GrabPose.NONE
var style_name := ""
var style_pose := StylePose.NONE
var grind_seconds := 0.0
var switch_takeoff := false
var air_seconds := 0.0
var grab_seconds := 0.0
var style_seconds := 0.0
var tweak_integral := 0.0
var dominant_kind := TrickCommand.Kind.NONE
var committed_axis_local := Vector3.ZERO
var rotation_axis_weights := Vector3.ZERO
var presentation_classifier := TrickPresentationClassifier.new()
var rail_pose := 0
var had_trick_intent := false
var air_presentation_eligible := true

func begin_air(
	is_switch: bool,
	takeoff_kind: int = TrickCommand.Kind.POP,
	presentation_eligible: bool = true,
	takeoff_axis_local: Vector3 = Vector3.ZERO
) -> void:
	active = true
	accumulated_rotation = Vector3.ZERO
	grab_name = ""
	live_grab_name = ""
	grab_contact_seconds = 0.0
	grab_qualified = false
	grab_pose = GrabPose.NONE
	style_name = ""
	style_pose = StylePose.NONE
	grind_seconds = 0.0
	switch_takeoff = is_switch
	air_seconds = 0.0
	grab_seconds = 0.0
	style_seconds = 0.0
	tweak_integral = 0.0
	committed_axis_local = takeoff_axis_local.normalized() if takeoff_axis_local.length_squared() > 0.0001 else Vector3.ZERO
	rotation_axis_weights = presentation_classifier.axis_weights(committed_axis_local)
	dominant_kind = presentation_classifier.classify(committed_axis_local, takeoff_kind)
	rail_pose = 0
	had_trick_intent = takeoff_kind not in [TrickCommand.Kind.NONE, TrickCommand.Kind.POP]
	air_presentation_eligible = presentation_eligible

func update_air(local_angular_velocity: Vector3, delta: float, command: TrickCommand = null) -> void:
	_update_air(local_angular_velocity, delta, command, false, Vector3.ZERO)

func update_air_authoritative(
	local_angular_velocity: Vector3,
	delta: float,
	command: TrickCommand,
	authoritative_rotation: Vector3
) -> void:
	_update_air(local_angular_velocity, delta, command, true, authoritative_rotation)

func _update_air(
	local_angular_velocity: Vector3,
	delta: float,
	command: TrickCommand,
	use_authoritative_rotation: bool,
	authoritative_rotation: Vector3
) -> void:
	if not active:
		return
	if command == null:
		command = TrickCommand.new()
	var previous_grab_name := grab_name
	air_seconds += delta
	if use_authoritative_rotation:
		accumulated_rotation = authoritative_rotation
	else:
		accumulated_rotation += local_angular_velocity * delta
	if command.rotation_axis_local.length_squared() > 0.0001:
		committed_axis_local = command.rotation_axis_local.normalized()
		rotation_axis_weights = presentation_classifier.axis_weights(committed_axis_local)
		dominant_kind = presentation_classifier.classify(committed_axis_local, dominant_kind)
	if command.committed and command.kind not in [TrickCommand.Kind.NONE, TrickCommand.Kind.POP]:
		dominant_kind = presentation_classifier.classify(committed_axis_local, command.kind)
		had_trick_intent = true
	grab_pose = command.grab_pose
	style_pose = command.style_pose
	if grab_pose != GrabPose.NONE:
		grab_seconds += delta * command.grab_amount
		tweak_integral = minf(tweak_integral + command.grab_tweak.length() * delta, MAX_TWEAK_INTEGRAL)
		had_trick_intent = true
	if style_pose != StylePose.NONE:
		style_seconds += delta * command.style_amount
		tweak_integral = minf(tweak_integral + command.grab_tweak.length() * delta, MAX_TWEAK_INTEGRAL)
		had_trick_intent = true
	# The live pose can return to neutral before touchdown, but the completed
	# trick still owns any grab that was held during the air. Keep the last
	# non-neutral name for scoring and the landing callout.
	if grab_pose != GrabPose.NONE:
		grab_name = GRAB_NAMES[grab_pose]
		if grab_name != previous_grab_name:
			live_grab_name = ""
			grab_contact_seconds = 0.0
			grab_qualified = false
	else:
		live_grab_name = ""
	if style_pose != StylePose.NONE:
		style_name = STYLE_NAMES[style_pose]
	trick_changed.emit(live_name())

func set_grab_contact(contact_weight: float, phase: String, delta: float) -> void:
	if not active or grab_name.is_empty():
		return
	var previous_live_name := live_grab_name
	var contact := contact_weight >= 0.48 and phase in ["CONTACT", "HOLD"]
	if contact:
		grab_contact_seconds += maxf(delta, 0.0)
		live_grab_name = grab_name
		if grab_contact_seconds >= MIN_GRAB_QUALIFY_TIME:
			grab_qualified = true
	elif phase in ["RELEASE", "RECOVER", "IDLE"] or grab_pose == GrabPose.NONE:
		live_grab_name = ""
	if previous_live_name != live_grab_name:
		trick_changed.emit(live_name())

func update_grind(delta: float, selected_pose: int = 0) -> void:
	active = true
	grind_seconds += delta
	rail_pose = selected_pose
	had_trick_intent = true
	var rail_name := "50-50" if rail_pose == 0 else ("Boardslide Left" if rail_pose < 0 else "Boardslide Right")
	trick_changed.emit("%s %.1fs" % [rail_name, grind_seconds])

func land(quality: float, switch_landing: bool, outcome: int, link_bonus: int = 0, rotation_quality_applied: bool = false) -> bool:
	if not active:
		return false
	var name := current_name()
	var spin_degrees := _spin_degrees()
	var flip_degrees := _flip_degrees()
	var cork_degrees := _cork_degrees()
	var motion_points := 0
	if dominant_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
		motion_points = cork_degrees * 3
	else:
		motion_points = spin_degrees * 2 + int(float(flip_degrees) / 360.0 * 500.0)
	var grind_points := int(minf(grind_seconds, MAX_GRIND_SCORE_SECONDS) * 300.0)
	var points: int = motion_points + grind_points
	if grab_qualified and not grab_name.is_empty():
		points += 150 + int(grab_seconds * 120.0) + int(minf(tweak_integral, MAX_TWEAK_INTEGRAL) * 80.0)
	if not style_name.is_empty():
		points += 150 + int(style_seconds * 120.0) + int(minf(tweak_integral, MAX_TWEAK_INTEGRAL) * 80.0)
	if switch_landing != switch_takeoff:
		name += " to Switch"
		points += 120
	if link_bonus > 0:
		name = "Line Link + " + name
		points += 200 * link_bonus
	if points <= 0 and grind_seconds < MIN_GRIND_SECONDS and dominant_kind == TrickCommand.Kind.POP and air_seconds >= MIN_STRAIGHT_AIR_PRESENTATION_TIME:
		points = 50
	if points <= 0 and grind_seconds < MIN_GRIND_SECONDS:
		reset()
		return false
	if points <= 0 and grind_seconds >= MIN_GRIND_SECONDS:
		points = grind_points
	var scored_quality := clampf(quality if rotation_quality_applied else quality * _rotation_quality_factor(), 0.2, 1.0)
	points = int(points * scored_quality)
	trick_landed.emit(name, points, scored_quality, outcome)
	reset()
	return true

func commit_grind() -> void:
	if grind_seconds < MIN_GRIND_SECONDS:
		grind_seconds = 0.0
		return
	var grind_points := int(minf(grind_seconds, MAX_GRIND_SCORE_SECONDS) * 300.0)
	if grind_points <= 0:
		grind_seconds = 0.0
		return
	var rail_name := "50-50" if rail_pose == 0 else ("Boardslide Left" if rail_pose < 0 else "Boardslide Right")
	trick_landed.emit("%s %.1fs" % [rail_name, grind_seconds], grind_points, 0.85, LandingSolver.Outcome.CLEAN)
	grind_seconds = 0.0

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
	if grab_qualified and not grab_name.is_empty():
		parts.append(grab_name)
	if not style_name.is_empty():
		parts.append(style_name)
	return "Straight Air" if parts.is_empty() else " + ".join(parts)

func live_name() -> String:
	var parts: Array[String] = []
	if grind_seconds > 0.0:
		parts.append("50-50" if rail_pose == 0 else ("Boardslide Left" if rail_pose < 0 else "Boardslide Right"))
	var yaw_degrees := maxi(0, int(round(rad_to_deg(absf(accumulated_rotation.y)))))
	var flip_degrees := maxi(0, int(round(rad_to_deg(absf(accumulated_rotation.x)))))
	var cork_degrees := maxi(yaw_degrees, int(round(rad_to_deg(absf(accumulated_rotation.z)))))
	if dominant_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
		parts.append("%s Cork %d°" % ["Left" if dominant_kind == TrickCommand.Kind.CORK_LEFT else "Right", cork_degrees])
	else:
		if dominant_kind in [TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT] or yaw_degrees >= 5:
			var spin_left := dominant_kind == TrickCommand.Kind.SPIN_LEFT or (
				dominant_kind not in [TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT]
				and accumulated_rotation.y < 0.0
			)
			parts.append("%s %d°" % ["Left" if spin_left else "Right", yaw_degrees])
		if dominant_kind in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP] or flip_degrees >= 5:
			var frontflip := dominant_kind == TrickCommand.Kind.FRONTFLIP or (
				dominant_kind not in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP]
				and accumulated_rotation.x > 0.0
			)
			parts.append("%s %d°" % ["Frontflip" if frontflip else "Backflip", flip_degrees])
	if not live_grab_name.is_empty():
		parts.append(live_grab_name)
	if not style_name.is_empty():
		parts.append(style_name)
	if parts.is_empty():
		return "Straight Air" if air_presentation_eligible and air_seconds >= MIN_STRAIGHT_AIR_PRESENTATION_TIME else ""
	return " + ".join(parts)

func rotation_target_degrees() -> int:
	return presentation_classifier.target_degrees(committed_axis_local, accumulated_rotation, dominant_kind)

func rotation_residual_degrees() -> float:
	return presentation_classifier.residual_degrees(committed_axis_local, accumulated_rotation, dominant_kind)

func rotation_snapshot() -> Dictionary:
	return {
		"target_degrees": rotation_target_degrees(),
		"residual_degrees": rotation_residual_degrees(),
		"accumulated_rotation": accumulated_rotation,
		"kind": dominant_kind,
		"axis_local": committed_axis_local,
		"axis_weights": rotation_axis_weights,
	}

func rotation_residual_vector() -> Vector3:
	return presentation_classifier.residual_vector(committed_axis_local, accumulated_rotation, dominant_kind)

func rotation_quality_factor() -> float:
	return _rotation_quality_factor()

func reset() -> void:
	active = false
	accumulated_rotation = Vector3.ZERO
	grab_name = ""
	live_grab_name = ""
	grab_contact_seconds = 0.0
	grab_qualified = false
	grab_pose = GrabPose.NONE
	style_name = ""
	style_pose = StylePose.NONE
	grind_seconds = 0.0
	air_seconds = 0.0
	grab_seconds = 0.0
	style_seconds = 0.0
	tweak_integral = 0.0
	dominant_kind = TrickCommand.Kind.NONE
	committed_axis_local = Vector3.ZERO
	rotation_axis_weights = Vector3.ZERO
	rail_pose = 0
	had_trick_intent = false
	air_presentation_eligible = true
	trick_changed.emit("")

func _spin_degrees() -> int:
	if dominant_kind in [TrickCommand.Kind.SPIN_LEFT, TrickCommand.Kind.SPIN_RIGHT]:
		return rotation_target_degrees()
	return _credited_degrees(rad_to_deg(absf(accumulated_rotation.y)), SPIN_STEP_DEGREES, SPIN_MAX_UNDERROTATION_DEGREES)

func _flip_degrees() -> int:
	if dominant_kind in [TrickCommand.Kind.FRONTFLIP, TrickCommand.Kind.BACKFLIP]:
		return rotation_target_degrees()
	return _credited_degrees(rad_to_deg(absf(accumulated_rotation.x)), FLIP_STEP_DEGREES, FLIP_MAX_UNDERROTATION_DEGREES)

func _cork_degrees() -> int:
	if dominant_kind in [TrickCommand.Kind.CORK_LEFT, TrickCommand.Kind.CORK_RIGHT]:
		return rotation_target_degrees()
	var amount := rad_to_deg(maxf(absf(accumulated_rotation.y), absf(accumulated_rotation.z)))
	return _credited_degrees(amount, SPIN_STEP_DEGREES, SPIN_MAX_UNDERROTATION_DEGREES)

func _credited_degrees(actual_degrees: float, step_degrees: float, max_underrotation_degrees: float) -> int:
	if actual_degrees + max_underrotation_degrees < step_degrees:
		return 0
	var steps := int(floor((actual_degrees + max_underrotation_degrees) / step_degrees))
	var credited := maxi(0, int(step_degrees) * steps)
	return mini(MAX_CREDITED_SPIN_DEGREES, credited)

func _rotation_quality_factor() -> float:
	var target := rotation_target_degrees()
	if target <= 0:
		return 1.0
	var residual := absf(rotation_residual_degrees())
	if residual <= CLEAN_ROTATION_RESIDUAL_DEGREES:
		return 1.0
	if residual <= SKETCHY_ROTATION_RESIDUAL_DEGREES:
		var t := (residual - CLEAN_ROTATION_RESIDUAL_DEGREES) / maxf(SKETCHY_ROTATION_RESIDUAL_DEGREES - CLEAN_ROTATION_RESIDUAL_DEGREES, 0.001)
		return lerpf(1.0, 0.6, t)
	return clampf(0.6 - (residual - SKETCHY_ROTATION_RESIDUAL_DEGREES) / 180.0, 0.25, 0.6)

func _style_pose_from_vector(style: Vector2) -> StylePose:
	if absf(style.x) > 0.45 and absf(style.x) >= absf(style.y):
		return StylePose.SHIFTY_LEFT if style.x < 0.0 else StylePose.SHIFTY_RIGHT
	if style.y < -0.45:
		return StylePose.SPREAD_EAGLE
	if style.y > 0.45:
		return StylePose.DAFFY
	return StylePose.NONE
