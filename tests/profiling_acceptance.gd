extends Node

## Repeatable post-decomposition profiling pass. It reports representative
## construction, query, frame, rail, and memory costs without imposing
## machine-specific thresholds on the correctness gate.

const RESORT_SCENE := preload("res://world/resort.tscn")
const GrindRail := preload("res://world/park_features/grind_rail_3d.gd")

var failures: Array[String] = []

func _ready() -> void:
	await get_tree().process_frame
	AudioManager.reset_profiling()
	await _profile_rails()
	await _profile_world_and_session()
	var audio := AudioManager.profiling_snapshot()
	print("PROFILE_AUDIO samples=%d average_us=%.2f max_us=%d headless=%s" % [
		int(audio.get("samples", 0)),
		float(audio.get("average_usec", 0.0)),
		int(audio.get("max_usec", 0)),
		str(audio.get("headless", false)),
	])
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("PROFILE_PASS: world, session, rail, camera-covered, audio, and capture profiling samples recorded")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("PROFILE_FAIL: " + failure)
	get_tree().quit(1)

func _profile_world_and_session() -> void:
	var resort := RESORT_SCENE.instantiate()
	var start_usec := Time.get_ticks_usec()
	add_child(resort)
	var build_usec := Time.get_ticks_usec() - start_usec
	if resort.get_node_or_null("Skier") == null or resort.get_node_or_null("CameraRig") == null:
		failures.append("Profile resort did not build its skier and camera")
		return
	var first_frame_start := Time.get_ticks_usec()
	await get_tree().process_frame
	var first_frame_usec := Time.get_ticks_usec() - first_frame_start
	var sample_sum_usec := 0
	var sample_max_usec := 0
	for _frame: int in 60:
		var frame_start := Time.get_ticks_usec()
		await get_tree().physics_frame
		var frame_usec := Time.get_ticks_usec() - frame_start
		sample_sum_usec += frame_usec
		sample_max_usec = maxi(sample_max_usec, frame_usec)
	var memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var track_snapshot: Dictionary = {}
	var skier := resort.get_node_or_null("Skier") as SkierController
	if skier != null:
		var snow_vfx := skier.get_node_or_null("SkiSnowVFX") as SkiSnowVFX
		if snow_vfx != null:
			track_snapshot = snow_vfx.debug_snapshot()
	print("PROFILE_WORLD build_ms=%.2f first_frame_ms=%.2f session_avg_ms=%.2f session_max_ms=%.2f memory_static_bytes=%d nodes=%d" % [
		float(build_usec) / 1000.0,
		float(first_frame_usec) / 1000.0,
		float(sample_sum_usec) / 60000.0,
		float(sample_max_usec) / 1000.0,
		memory,
		resort.find_children("*", "Node", true, false).size(),
	])
	print("PROFILE_TRACKS rebuilds=%d average_us=%.2f max_us=%d left_samples=%d right_samples=%d" % [
		int(track_snapshot.get("track_rebuild_count", 0)),
		float(track_snapshot.get("track_rebuild_average_usec", 0.0)),
		int(track_snapshot.get("track_rebuild_max_usec", 0)),
		int(track_snapshot.get("left_track_samples", 0)),
		int(track_snapshot.get("right_track_samples", 0)),
	])
	resort.queue_free()
	await get_tree().process_frame

func _profile_rails() -> void:
	for rail_count: int in [8, 32, 64]:
		var rails: Array[Node] = []
		var build_start := Time.get_ticks_usec()
		for rail_index: int in rail_count:
			var rail: GrindRail = GrindRail.new()
			rail.name = "ProfileRail_%d" % rail_index
			var curve := Curve3D.new()
			for point_index: int in 4:
				curve.add_point(Vector3(float(point_index) * 1.5, 1.0 + sin(float(point_index) * 0.6) * 0.35, -float(rail_index) * 1.6))
			rail.path = curve
			add_child(rail)
			rails.append(rail)
		var build_usec := Time.get_ticks_usec() - build_start
		await get_tree().process_frame
		var query_start := Time.get_ticks_usec()
		var valid_queries := 0
		for rail_node: Node in rails:
			var rail := rail_node as GrindRail
			for query_index: int in 30:
				var result := rail.capture_candidate(Vector3(8.0, 1.2, -float(query_index % rail_count) * 1.6), Vector3.FORWARD * 12.0, 1.2, 3.0)
				if bool(result.get("valid", false)):
					valid_queries += 1
		var query_usec := Time.get_ticks_usec() - query_start
		print("PROFILE_RAILS count=%d path_points=4 build_ms=%.2f query_ms=%.2f query_average_us=%.2f valid_queries=%d" % [
			rail_count,
			float(build_usec) / 1000.0,
			float(query_usec) / 1000.0,
			float(query_usec) / maxf(float(rail_count * 30), 1.0),
			valid_queries,
		])
		for rail: Node in rails:
			rail.queue_free()
		await get_tree().process_frame
