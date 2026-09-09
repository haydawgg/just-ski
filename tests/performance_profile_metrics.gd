class_name PerformanceProfileMetrics
extends RefCounted

const RuntimeEnvironment := preload("res://util/runtime_environment.gd")
const SCHEMA_VERSION := "1.0"

static func summarize_frame_times(samples: Array) -> Dictionary:
	var sorted_samples: Array[float] = []
	var total := 0.0
	for value: Variant in samples:
		var frame_ms := float(value)
		if not is_finite(frame_ms) or frame_ms < 0.0:
			continue
		sorted_samples.append(frame_ms)
		total += frame_ms
	sorted_samples.sort()
	if sorted_samples.is_empty():
		return {
			"samples": 0,
			"average_ms": 0.0,
			"minimum_ms": 0.0,
			"maximum_ms": 0.0,
			"p50_ms": 0.0,
			"p95_ms": 0.0,
			"p99_ms": 0.0,
		}
	return {
		"samples": sorted_samples.size(),
		"average_ms": total / float(sorted_samples.size()),
		"minimum_ms": sorted_samples.front(),
		"maximum_ms": sorted_samples.back(),
		"p50_ms": _nearest_rank(sorted_samples, 0.50),
		"p95_ms": _nearest_rank(sorted_samples, 0.95),
		"p99_ms": _nearest_rank(sorted_samples, 0.99),
	}

static func make_profile(
	environment_name: String,
	preset_name: String,
	scenario_name: String,
	commit_sha: String,
	working_tree_dirty: bool,
	frame_times_ms: Array,
	render_metrics: Dictionary,
	audio_metrics: Dictionary
) -> Dictionary:
	var identity := {
		"environment": environment_name,
		"preset": preset_name,
		"scenario": scenario_name,
		"commit_sha": commit_sha,
		"working_tree_dirty": working_tree_dirty,
	}
	var runtime := {
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"platform": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"headless": RuntimeEnvironment.is_headless(),
		"processor_count": OS.get_processor_count(),
		"processor_name": OS.get_processor_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_adapter_vendor": RenderingServer.get_video_adapter_vendor(),
	}
	return {
		"schema_version": SCHEMA_VERSION,
		"captured_at_utc": Time.get_datetime_string_from_system(true, true),
		"identity": identity,
		"runtime": runtime,
		"frames": summarize_frame_times(frame_times_ms),
		"render": render_metrics.duplicate(true),
		"audio": audio_metrics.duplicate(true),
	}

static func validate_profile(profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if profile.get("schema_version", "") != SCHEMA_VERSION:
		errors.append("schema_version must equal %s" % SCHEMA_VERSION)
	_validate_keys(profile, ["captured_at_utc", "identity", "runtime", "frames", "render", "audio"], "profile", errors)
	var identity := profile.get("identity", {}) as Dictionary
	_validate_keys(identity, ["environment", "preset", "scenario", "commit_sha", "working_tree_dirty"], "identity", errors)
	var frames := profile.get("frames", {}) as Dictionary
	_validate_keys(frames, ["samples", "average_ms", "minimum_ms", "maximum_ms", "p50_ms", "p95_ms", "p99_ms"], "frames", errors)
	var render := profile.get("render", {}) as Dictionary
	_validate_keys(render, ["objects", "primitives", "draw_calls", "video_memory_bytes", "texture_memory_bytes", "buffer_memory_bytes"], "render", errors)
	return {"valid": errors.is_empty(), "errors": errors}

static func _nearest_rank(sorted_samples: Array[float], percentile: float) -> float:
	var rank := ceili(clampf(percentile, 0.0, 1.0) * float(sorted_samples.size()))
	return sorted_samples[clampi(rank - 1, 0, sorted_samples.size() - 1)]

static func _validate_keys(value: Dictionary, keys: Array[String], label: String, errors: Array[String]) -> void:
	for key: String in keys:
		if not value.has(key):
			errors.append("%s is missing %s" % [label, key])
