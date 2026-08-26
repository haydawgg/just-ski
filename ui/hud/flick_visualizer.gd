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
var path := PackedVector2Array()
var linger_time := 0.0
var title_label: Label
var detail_label: Label

func _ready() -> void:
	name = "TrickVisualizer"
	custom_minimum_size = Vector2(250.0, 200.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = Label.new()
	title_label.position = Vector2(8.0, 5.0)
	title_label.add_theme_font_size_override("font_size", 16)
	add_child(title_label)
	detail_label = Label.new()
	detail_label.position = Vector2(8.0, 174.0)
	detail_label.add_theme_font_size_override("font_size", 12)
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
	if path.is_empty() or path[path.size() - 1].distance_to(stick) > 0.035:
		path.append(stick)
		if path.size() > MAX_PATH_POINTS:
			path.remove_at(0)
	var active := stick.length() > 0.08 or left_trigger > 0.05 or right_trigger > 0.05 or phase not in ["NEUTRAL", "LANDING"]
	if active:
		linger_time = 0.55
	visible = bool(GameSettings.active.get("trick_visualizer_enabled", true)) and (active or linger_time > 0.0)
	title_label.text = _pretty(kind)
	detail_label.text = "%s  •  %d%%  •  %s" % [_pretty(phase), roundi(strength * 100.0), grab if not grab.is_empty() else "NO GRAB"]
	queue_redraw()

func debug_snapshot() -> Dictionary:
	return {"kind": kind, "phase": phase, "path_points": path.size(), "left_trigger": left_trigger, "right_trigger": right_trigger}

func _process(delta: float) -> void:
	if linger_time > 0.0:
		linger_time -= delta
	elif stick.length() <= 0.08 and left_trigger <= 0.05 and right_trigger <= 0.05:
		visible = false
		path.clear()

func _draw() -> void:
	var center := Vector2(125.0, 104.0)
	var radius := 54.0
	draw_circle(center, radius + 7.0, Color(0.02, 0.06, 0.09, 0.78))
	draw_arc(center, radius, 0.0, TAU, 48, Color("#d8f4ff"), 2.0, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), Color(0.5, 0.7, 0.78, 0.35), 1.0)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), Color(0.5, 0.7, 0.78, 0.35), 1.0)
	if path.size() > 1:
		var points := PackedVector2Array()
		for value: Vector2 in path:
			points.append(center + Vector2(value.x, value.y) * radius)
		draw_polyline(points, Color("#ffc857"), 3.0, true)
	draw_circle(center + Vector2(stick.x, stick.y) * radius, 6.0, Color("#ff6b7d"))
	draw_rect(Rect2(18.0, 156.0 - left_trigger * 38.0, 13.0, left_trigger * 38.0), Color("#5ac8fa"))
	draw_rect(Rect2(219.0, 156.0 - right_trigger * 38.0, 13.0, right_trigger * 38.0), Color("#5ac8fa"))

func _pretty(value: String) -> String:
	return value.replace("_", " ").capitalize()
