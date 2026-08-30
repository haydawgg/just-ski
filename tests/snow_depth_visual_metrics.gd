extends Node

const DEFAULT_CAPTURE_DIRECTORY := "res://.godot_user/captures/phase_15_after"
const SAMPLE_STEP := 2
const ROI_X_MIN := 0.04
const ROI_X_MAX := 0.96
const ROI_Y_MIN := 0.42
const ROI_Y_MAX := 0.88
const MIN_SNOW_VALUE_SPREAD := 0.10
const MAX_BLUE_SHADOW_COVERAGE := 0.35


func _ready() -> void:
	var capture_directory := DEFAULT_CAPTURE_DIRECTORY
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	var directory := DirAccess.open(capture_directory)
	if directory == null:
		push_error("SNOW_DEPTH_VISUAL_FAIL: capture directory is unavailable: %s" % capture_directory)
		call_deferred("_finish", 1)
		return
	var filenames: PackedStringArray = []
	for filename: String in directory.get_files():
		if filename.get_extension().to_lower() == "png":
			filenames.append(filename)
	filenames.sort()
	if filenames.is_empty():
		push_error("SNOW_DEPTH_VISUAL_FAIL: no PNG captures found in %s" % capture_directory)
		call_deferred("_finish", 1)
		return
	var spread_sum := 0.0
	var maximum_blue_shadow_coverage := 0.0
	for filename: String in filenames:
		var metrics := _measure_image(capture_directory.path_join(filename))
		if metrics.is_empty():
			call_deferred("_finish", 1)
			return
		spread_sum += float(metrics.snow_value_spread)
		maximum_blue_shadow_coverage = maxf(maximum_blue_shadow_coverage, float(metrics.blue_shadow_coverage))
		print("SNOW_DEPTH_VISUAL_METRIC: %s snow_value_spread=%.3f blue_shadow_coverage=%.3f" % [filename, metrics.snow_value_spread, metrics.blue_shadow_coverage])
	var failures: Array[String] = []
	var average_spread := spread_sum / float(filenames.size())
	if average_spread < MIN_SNOW_VALUE_SPREAD:
		failures.append("average snow value p10-p90 spread %.3f is below %.3f" % [average_spread, MIN_SNOW_VALUE_SPREAD])
	if maximum_blue_shadow_coverage > MAX_BLUE_SHADOW_COVERAGE:
		failures.append("blue shadow coverage %.3f exceeds %.3f" % [maximum_blue_shadow_coverage, MAX_BLUE_SHADOW_COVERAGE])
	if failures.is_empty():
		print("SNOW_DEPTH_VISUAL_PASS: restrained snow value separation and bounded blue shadow coverage")
		call_deferred("_finish", 0)
	else:
		for failure: String in failures:
			push_error("SNOW_DEPTH_VISUAL_FAIL: " + failure)
		call_deferred("_finish", 1)


func _finish(exit_code: int) -> void:
	get_tree().quit(exit_code)


func _measure_image(path: String) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("SNOW_DEPTH_VISUAL_FAIL: could not load capture: %s" % path)
		return {}
	var width := image.get_width()
	var height := image.get_height()
	var snow_values: Array[float] = []
	var blue_shadow_samples := 0
	var sample_count := 0
	for y: int in range(int(height * ROI_Y_MIN), int(height * ROI_Y_MAX), SAMPLE_STEP):
		for x: int in range(int(width * ROI_X_MIN), int(width * ROI_X_MAX), SAMPLE_STEP):
			var color := image.get_pixel(x, y)
			var value_max := maxf(color.r, maxf(color.g, color.b))
			var value_min := minf(color.r, minf(color.g, color.b))
			var chroma := value_max - value_min
			var luminance := color.get_luminance()
			sample_count += 1
			# Include both lit and shadow-side snow; saturated park colors and dark
			# character/terrain pixels remain excluded by the neutral/value gates.
			if chroma < 0.13 and luminance > 0.58:
				snow_values.append(luminance)
			if color.b - color.r > 0.08 and luminance < 0.55:
				blue_shadow_samples += 1
	if snow_values.size() < 100:
		push_error("SNOW_DEPTH_VISUAL_FAIL: capture does not contain enough snow samples: %s" % path)
		return {}
	snow_values.sort()
	var p10 := snow_values[int(snow_values.size() * 0.10)]
	var p90 := snow_values[int(snow_values.size() * 0.90)]
	return {
		"snow_value_spread": p90 - p10,
		"blue_shadow_coverage": float(blue_shadow_samples) / float(sample_count),
	}
