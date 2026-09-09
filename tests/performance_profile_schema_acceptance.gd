extends Node

const ProfileMetrics := preload("res://tests/performance_profile_metrics.gd")
const RuntimeEnvironment := preload("res://util/runtime_environment.gd")

var failures: Array[String] = []

func _ready() -> void:
	_test_percentiles()
	_test_schema_contract()
	if failures.is_empty():
		print("PERFORMANCE_PROFILE_SCHEMA_PASS: percentile summaries and comparable profile identity passed")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("PERFORMANCE_PROFILE_SCHEMA_FAIL: " + failure)
	get_tree().quit(1)

func _test_percentiles() -> void:
	var summary := ProfileMetrics.summarize_frame_times([10.0, 20.0, 30.0, 40.0, 50.0])
	if not is_equal_approx(float(summary.get("average_ms", 0.0)), 30.0):
		failures.append("Frame summary did not report the known 30 ms average")
	if not is_equal_approx(float(summary.get("p50_ms", 0.0)), 30.0):
		failures.append("Frame summary did not report the known 30 ms median")
	if not is_equal_approx(float(summary.get("p95_ms", 0.0)), 50.0):
		failures.append("Frame summary did not report the nearest-rank 50 ms p95")
	if int(summary.get("samples", 0)) != 5:
		failures.append("Frame summary did not retain its sample count")

func _test_schema_contract() -> void:
	var profile := ProfileMetrics.make_profile(
		"daytime",
		"fast",
		"baseline",
		"012a0d40",
		true,
		[12.0, 16.0, 20.0],
		{
			"draw_calls": 120,
			"objects": 240,
			"primitives": 360,
			"video_memory_bytes": 1024,
			"texture_memory_bytes": 512,
			"buffer_memory_bytes": 256,
		},
		{"average_usec": 250.0, "max_usec": 400}
	)
	var validation := ProfileMetrics.validate_profile(profile)
	if not bool(validation.get("valid", false)):
		failures.append("A complete profile failed validation: %s" % str(validation.get("errors", [])))
	if profile.get("schema_version", "") != ProfileMetrics.SCHEMA_VERSION:
		failures.append("Profile did not publish the current schema version")
	var identity := profile.get("identity", {}) as Dictionary
	if identity.get("environment", "") != "daytime" or identity.get("scenario", "") != "baseline":
		failures.append("Profile identity did not retain environment and scenario")
	var runtime := profile.get("runtime", {}) as Dictionary
	if not runtime.has("headless") or bool(runtime.get("headless")) != RuntimeEnvironment.is_headless():
		failures.append("Profile runtime.headless does not match the active runtime environment")
	var incomplete := profile.duplicate(true)
	incomplete.erase("render")
	if bool(ProfileMetrics.validate_profile(incomplete).get("valid", true)):
		failures.append("Schema validation accepted a profile without render metrics")
