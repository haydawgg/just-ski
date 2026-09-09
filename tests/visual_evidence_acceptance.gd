extends Node

const VisualEvidence := preload("res://tests/visual_evidence.gd")

var failures: Array[String] = []


func _ready() -> void:
	var root := "res://.godot_user/visual_evidence_acceptance"
	var session := VisualEvidence.begin({
		"suite_id": "acceptance",
		"evidence_root": root,
		"capture_width": 8,
		"capture_height": 4,
		"fixed_fps": 60,
		"context": {
			"environment": "fixture",
			"preset": "acceptance",
			"seed": 17,
		},
	})
	var image := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color("#72a6c8"))
	var z_path := session.capture_image("acceptance.zeta", "raw", image, {
		"artifact_filename": "zeta.png",
		"state": "FIXTURE",
		"phase": "second",
		"view": "fixture",
	})
	var a_path := session.capture_image("acceptance.alpha", "raw", image, {
		"artifact_filename": "alpha.png",
		"state": "FIXTURE",
		"phase": "first",
		"view": "fixture",
	})
	session.record_sample("acceptance.zeta", {
		"time_s": 0.25,
		"position_m": Vector3(1.0, 2.0, 3.0),
		"rotation_rad": Vector3(0.1, 0.2, 0.3),
		"transform": Transform3D(Basis.IDENTITY, Vector3(4.0, 5.0, 6.0)),
		"finite": true,
	})
	session.record_sample("acceptance.zeta", {
		"time_s": 0.50,
		"position_m": [1.1, 2.0, 3.2],
		"rotation_rad": [0.1, 0.25, 0.35],
		"finite": true,
	})
	session.record_check("acceptance.structured_telemetry", "schema", "pass", {
		"position_m": VisualEvidence.normalize(Vector3.ONE),
		"rotation_rad": VisualEvidence.normalize(Vector3.ZERO),
	}, [3, 3], "Vector telemetry normalizes to numeric arrays")
	session.write_json_artifact("acceptance.metadata", "metadata", "fixture.json", {
		"schema_version": "visual-evidence-v1",
		"units": {"position": "m", "rotation": "rad"},
	}, {})
	var unsafe_existing := ProjectSettings.globalize_path("res://tests/visual_evidence.gd")
	var rejected := session.register_file_artifact("acceptance.zeta", "unsafe", unsafe_existing)
	if not rejected.is_empty():
		failures.append("register_file_artifact accepted a file outside the evidence root")
	session.record_check("artifact:acceptance.zeta:unsafe", "path_containment", "advisory", null, null, "Outside-root artifact was rejected")
	var manifest := session.finish(0)
	if manifest.is_empty():
		failures.append("finish did not return a manifest")
	if str(manifest.get("status", "")) != "pass":
		failures.append("fixture manifest did not pass: %s" % manifest.get("status", "missing"))
	if z_path.is_empty() or a_path.is_empty():
		failures.append("fixture images were not captured")
	var artifact_rows: Array = manifest.get("artifacts", []) as Array
	if artifact_rows.size() < 4:
		failures.append("manifest did not include the two images, metadata, and telemetry artifacts")
	var previous_path := ""
	for artifact_variant: Variant in artifact_rows:
		var artifact := artifact_variant as Dictionary
		var artifact_path := str(artifact.get("path", ""))
		if artifact_path < previous_path:
			failures.append("manifest artifact ordering is not deterministic")
		previous_path = artifact_path
		if ".." in artifact_path or artifact_path.begins_with("/"):
			failures.append("manifest contains an unsafe artifact path: %s" % artifact_path)
		if artifact.get("format") == "png" and (int(artifact.get("width", 0)) != 8 or int(artifact.get("height", 0)) != 4):
			failures.append("fixture image dimensions were not normalized to the configured capture size")
		if artifact.get("format") == "png" and str(artifact.get("sha256", "")).length() != 64:
			failures.append("fixture image did not receive a SHA-256 hash")
	var telemetry_path := root.path_join("telemetry").path_join("acceptance.zeta").path_join("samples.json")
	if not FileAccess.file_exists(telemetry_path):
		failures.append("structured telemetry was not written")
	else:
		var telemetry: Variant = JSON.parse_string(FileAccess.get_file_as_string(telemetry_path))
		var first_sample := ((telemetry as Dictionary).get("samples", []) as Array).front() as Dictionary
		if not (first_sample.get("position_m", []) is Array) or (first_sample.get("position_m", []) as Array).size() != 3:
			failures.append("structured position telemetry was serialized incorrectly")
		var transform_value: Variant = first_sample.get("transform", {})
		if not (transform_value is Dictionary) or not ((transform_value as Dictionary).get("origin_m", []) is Array) or ((transform_value as Dictionary).get("origin_m", []) as Array).size() != 3:
			failures.append("structured transform telemetry was serialized incorrectly")
	var unsafe_session := VisualEvidence.begin({
		"suite_id": "unsafe_acceptance",
		"evidence_root": "res://tests/should_not_be_an_evidence_root",
	})
	if not unsafe_session.get_root_path().replace("\\", "/").contains("/.godot_user/"):
		failures.append("unsafe evidence root did not fall back inside .godot_user")
	if failures.is_empty():
		print("VISUAL_EVIDENCE_ACCEPTANCE_PASS: manifest ordering, structured telemetry, hashes, dimensions, and path containment")
	else:
		for failure: String in failures:
			push_error("VISUAL_EVIDENCE_ACCEPTANCE_FAIL: " + failure)
	AudioManager.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
