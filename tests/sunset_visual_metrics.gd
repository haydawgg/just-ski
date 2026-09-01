extends Node

## Pixel-level guard for the sunset capture's known foreground artifact. This
## intentionally runs after the GPU-backed capture scene; it is not a headless
## renderer test.

const DEFAULT_CAPTURE_PATH := "res://.godot_user/captures/sunset_resort.png"
const ROI := Rect2(0.04, 0.42, 0.92, 0.48)
const SKIER_MASK := Rect2(0.40, 0.18, 0.20, 0.46)
const TOP_HUD_MASK := Rect2(0.0, 0.0, 1.0, 0.12)
const BOTTOM_HUD_MASK := Rect2(0.0, 0.90, 1.0, 0.10)
const SAMPLE_STEP := 2
const DARK_MAX_CHANNEL := 0.16
const DARK_LUMINANCE := 0.12
const MAX_DARK_COMPONENT_ROI_FRACTION := 0.02


func _ready() -> void:
	var capture_path := DEFAULT_CAPTURE_PATH
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-path="):
			capture_path = argument.trim_prefix("--capture-path=")
	var image := Image.load_from_file(ProjectSettings.globalize_path(capture_path))
	if image == null or image.is_empty():
		push_error("SUNSET_VISUAL_METRIC_FAIL: capture is unavailable: %s" % capture_path)
		get_tree().quit(1)
		return
	if image.get_width() != 1280 or image.get_height() != 720:
		push_error("SUNSET_VISUAL_METRIC_FAIL: expected a 1280x720 capture, got %dx%d" % [image.get_width(), image.get_height()])
		get_tree().quit(1)
		return
	var result := _measure_dark_components(image)
	print("SUNSET_VISUAL_METRIC: path=%s largest_dark_component=%.3f roi_components=%d" % [
		capture_path,
		result.largest_component_roi_fraction,
		result.component_count,
	])
	if result.largest_component_roi_fraction > MAX_DARK_COMPONENT_ROI_FRACTION:
		push_error("SUNSET_VISUAL_METRIC_FAIL: lower-frame near-black component %.3f exceeds %.3f of the gameplay ROI" % [
			result.largest_component_roi_fraction,
			MAX_DARK_COMPONENT_ROI_FRACTION,
		])
		get_tree().quit(1)
		return
	print("SUNSET_VISUAL_METRIC_PASS: no oversized near-black lower-frame region")
	get_tree().quit(0)


func _measure_dark_components(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var roi_min_x := clampi(int(width * ROI.position.x), 0, width)
	var roi_max_x := clampi(int(width * (ROI.position.x + ROI.size.x)), 0, width)
	var roi_min_y := clampi(int(height * ROI.position.y), 0, height)
	var roi_max_y := clampi(int(height * (ROI.position.y + ROI.size.y)), 0, height)
	var sample_width := maxi(ceili(float(roi_max_x - roi_min_x) / SAMPLE_STEP), 1)
	var sample_height := maxi(ceili(float(roi_max_y - roi_min_y) / SAMPLE_STEP), 1)
	var dark := PackedByteArray()
	dark.resize(sample_width * sample_height)
	for sample_y: int in range(sample_height):
		var y := mini(roi_min_y + sample_y * SAMPLE_STEP, roi_max_y - 1)
		for sample_x: int in range(sample_width):
			var x := mini(roi_min_x + sample_x * SAMPLE_STEP, roi_max_x - 1)
			if _masked_pixel(x, y, width, height):
				continue
			var color := image.get_pixel(x, y)
			var maximum_channel := maxf(color.r, maxf(color.g, color.b))
			if maximum_channel < DARK_MAX_CHANNEL and color.get_luminance() < DARK_LUMINANCE:
				dark[sample_y * sample_width + sample_x] = 1

	var visited := PackedByteArray()
	visited.resize(dark.size())
	var largest_component := 0
	var component_count := 0
	for sample_y: int in range(sample_height):
		for sample_x: int in range(sample_width):
			var start_index := sample_y * sample_width + sample_x
			if dark[start_index] == 0 or visited[start_index] != 0:
				continue
			component_count += 1
			var stack: Array[int] = [start_index]
			visited[start_index] = 1
			var component_size := 0
			while not stack.is_empty():
				var current: int = stack.pop_back()
				component_size += 1
				var current_x: int = current % sample_width
				var current_y: int = current / sample_width
				if current_x > 0:
					_add_component_neighbor(current - 1, dark, visited, stack)
				if current_x + 1 < sample_width:
					_add_component_neighbor(current + 1, dark, visited, stack)
				if current_y > 0:
					_add_component_neighbor(current - sample_width, dark, visited, stack)
				if current_y + 1 < sample_height:
					_add_component_neighbor(current + sample_width, dark, visited, stack)
			largest_component = maxi(largest_component, component_size)

	var roi_area := float(maxi(roi_max_x - roi_min_x, 1) * maxi(roi_max_y - roi_min_y, 1))
	var sampled_component_area := float(largest_component * SAMPLE_STEP * SAMPLE_STEP)
	return {
		"largest_component_roi_fraction": sampled_component_area / roi_area,
		"component_count": component_count,
	}


func _add_component_neighbor(index: int, dark: PackedByteArray, visited: PackedByteArray, stack: Array[int]) -> void:
	if dark[index] == 0 or visited[index] != 0:
		return
	visited[index] = 1
	stack.append(index)


func _masked_pixel(x: int, y: int, width: int, height: int) -> bool:
	var normalized := Vector2(float(x) / maxf(width - 1, 1), float(y) / maxf(height - 1, 1))
	return TOP_HUD_MASK.has_point(normalized) or BOTTOM_HUD_MASK.has_point(normalized) or SKIER_MASK.has_point(normalized)
