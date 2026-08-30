class_name FlickVisualizer
extends Control

const MAX_PATH_POINTS := 20

var stick := Vector2.ZERO
var kind := "NONE"
var phase := "NEUTRAL"
var strength := 0.0
var left_trigger := 0.0
var right_trigger := 0.0
var grab := ""
var trick_text := ""
var yaw_degrees := 0
var flip_degrees := 0
var cork_degrees := 0
var accumulated_rotation := Vector3.ZERO
var path := PackedVector2Array()
var linger_time := 0.0
var title_label: Label
var detail_label: Label

func _ready() -> void:
	name = "TrickVisualizer"
	custom_minimum_size = Vector2(190.0, 150.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.position = Vector2(8.0, 3.0)
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", Color("#d9eef2"))
	title_label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.09, 0.42))
	title_label.add_theme_constant_override("outline_size", 2)
	add_child(title_label)
	detail_label = Label.new()
	detail_label.position = Vector2(8.0, 130.0)
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color("#b6d1d7"))
	detail_label.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.09, 0.34))
	detail_label.add_theme_constant_override("outline_size", 2)
	add_child(detail_label)
	visible = false
	set_process(true)

func apply_snapshot(data: Dictionary) -> void:
	stick = data.get("stick", Vector2.ZERO) as Vector2
	kind = str(data.get("kind", "NONE"))
	phase = str(data.get("phase", "NEUTRAL"))
	strength = float(data.get("strength", 0.0))
	left_trigger = float(data.get("left_trigger", 0.0))
	right_trigger = float(data.get("right_trigger", 0.0))
	grab = str(data.get("grab", ""))
	trick_text = str(data.get("trick_text", ""))
	yaw_degrees = int(data.get("yaw_degrees", 0))
	flip_degrees = int(data.get("flip_degrees", 0))
	cork_degrees = int(data.get("cork_degrees", 0))
	accumulated_rotation = data.get("accumulated_rotation", Vector3.ZERO) as Vector3
	if path.is_empty() or path[path.size() - 1].distance_to(stick) > 0.035:
		path.append(stick)
		if path.size() > MAX_PATH_POINTS:
			path.remove_at(0)
	var direct_input := stick.length() > 0.14 or left_trigger > 0.08 or right_trigger > 0.08
	var gesture_event := phase in ["PRELOAD", "FLICK", "ROTATE"] and strength > 0.2
	var active := direct_input or gesture_event
	if active:
		linger_time = 0.16
	visible = bool(GameSettings.active.get("trick_visualizer_enabled", true)) and (active or linger_time > 0.0)
	modulate.a = 0.62 if active else clampf(linger_time / 0.16, 0.0, 0.34)
	if not trick_text.is_empty():
		title_label.text = trick_text
	else:
		title_label.text = _pretty(kind)
	var base_detail := "%s  •  %d%%  •  %s" % [_pretty(phase), roundi(strength * 100.0), grab if not grab.is_empty() else "NO GRAB"]
	if trick_text.contains(" + ") or (yaw_degrees >= 5 and flip_degrees >= 5):
		base_detail += "  •  Y:%d° F:%d°" % [yaw_degrees, flip_degrees]
	elif yaw_degrees >= 5 and flip_degrees < 5 and yaw_degrees >= 10:
		base_detail += "  •  Y:%d°" % yaw_degrees
	elif flip_degrees >= 5 and yaw_degrees < 5 and flip_degrees >= 10:
		base_detail += "  •  F:%d°" % flip_degrees
	detail_label.text = base_detail
	queue_redraw()

func debug_snapshot() -> Dictionary:
	return {"kind": kind, "phase": phase, "path_points": path.size(), "left_trigger": left_trigger, "right_trigger": right_trigger, "trick_text": trick_text, "yaw_degrees": yaw_degrees, "flip_degrees": flip_degrees}

func _process(delta: float) -> void:
	if linger_time > 0.0:
		linger_time = maxf(0.0, linger_time - delta)
	if linger_time <= 0.0 and stick.length() <= 0.14 and left_trigger <= 0.08 and right_trigger <= 0.08:
		visible = false
		path.clear()

func _draw() -> void:
	var center := Vector2(95.0, 78.0)
	var radius := 39.0
	draw_circle(center, radius + 6.0, Color(0.02, 0.06, 0.09, 0.34))
	draw_arc(center, radius, 0.0, TAU, 40, Color(0.75, 0.89, 0.92, 0.54), 1.25, true)
	# Multi-axis yaw / flip arcs ensure the visualizer represents the same composite rotation as trick_text.
	if yaw_degrees >= 5:
		var yaw_rad := deg_to_rad(clampf(float(mini(yaw_degrees, 360)), 0.0, 360.0))
		draw_arc(center, radius + 2.0, -PI * 0.5, -PI * 0.5 + yaw_rad, 28, Color("#6ecff6", 0.78), 2.2, true)
	if flip_degrees >= 5:
		var flip_rad := deg_to_rad(clampf(float(mini(flip_degrees, 360)), 0.0, 360.0))
		draw_arc(center, radius + 5.5, -PI * 0.5, -PI * 0.5 + flip_rad, 28, Color("#ff7eb8", 0.78), 2.2, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), Color(0.5, 0.7, 0.78, 0.35), 1.0)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), Color(0.5, 0.7, 0.78, 0.35), 1.0)
	if path.size() > 1:
		var points := PackedVector2Array()
		for value: Vector2 in path:
			points.append(center + Vector2(value.x, value.y) * radius)
		draw_polyline(points, Color("#dbc077"), 2.0, true)
	draw_circle(center + Vector2(stick.x, stick.y) * radius, 4.5, Color("#d4777f"))
	draw_rect(Rect2(14.0, 118.0 - left_trigger * 28.0, 9.0, left_trigger * 28.0), Color("#73aebe"))
	draw_rect(Rect2(167.0, 118.0 - right_trigger * 28.0, 9.0, right_trigger * 28.0), Color("#73aebe"))

func _pretty(value: String) -> String:
	return value.replace("_", " ").capitalize()
