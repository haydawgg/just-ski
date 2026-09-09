class_name VisualEvidenceSession
extends RefCounted

## Shared evidence seam for rendered visual tests.
##
## Capture scenes should only describe the scenario being observed. This module
## owns output layout, JSON normalization, per-scenario telemetry, and the
## suite manifest so a caller never has to invent another capture directory.

const SCHEMA_VERSION := "visual-evidence-v1"
const DEFAULT_CATALOG_PATH := "res://tests/visual_scenarios.json"
const DEFAULT_WIDTH := 1280
const DEFAULT_HEIGHT := 720
const VALID_STATUSES := ["pass", "fail", "advisory", "review_required", "not_comparable", "missing"]

var root_path := ""
var suite_id := "unknown"
var catalog_path := DEFAULT_CATALOG_PATH
var capture_size := Vector2i(DEFAULT_WIDTH, DEFAULT_HEIGHT)
var fixed_fps := 0
var started_at_utc := ""
var context: Dictionary = {}
var catalog: Dictionary = {}
var scenarios: Dictionary = {}
var artifacts: Array[Dictionary] = []
var samples: Dictionary = {}
var checks: Array[Dictionary] = []
var review_items: Array[Dictionary] = []
var errors: Array[String] = []
var finished := false


static func begin(config: Dictionary = {}) -> VisualEvidenceSession:
	var session := VisualEvidenceSession.new()
	session._initialize(config)
	return session


static func normalize(value: Variant) -> Variant:
	return _normalize_value(value)


func _initialize(config: Dictionary) -> void:
	suite_id = str(config.get("suite_id", "unknown"))
	catalog_path = str(config.get("scenario_catalog_path", DEFAULT_CATALOG_PATH))
	fixed_fps = int(config.get("fixed_fps", 0))
	var width := int(config.get("capture_width", DEFAULT_WIDTH))
	var height := int(config.get("capture_height", DEFAULT_HEIGHT))
	capture_size = Vector2i(maxi(width, 1), maxi(height, 1))
	context = normalize(config.get("context", {})) as Dictionary
	context["suite_id"] = suite_id
	context["fixed_fps"] = fixed_fps
	context["capture_width"] = capture_size.x
	context["capture_height"] = capture_size.y
	context["resolution"] = [capture_size.x, capture_size.y]
	context["godot_version"] = str(context.get("godot_version", Engine.get_version_info().get("string", "unknown")))
	var renderer_name := str(context.get("renderer", ProjectSettings.get_setting("rendering/renderer/rendering_method", "Forward Plus")))
	match renderer_name.to_lower().replace(" ", "_"):
		"forward_plus", "forward+":
			renderer_name = "Forward Plus"
		"gl_compatibility", "compatibility":
			renderer_name = "Compatibility"
	context["renderer"] = renderer_name
	context["gpu"] = str(context.get("gpu", RenderingServer.get_video_adapter_name()))
	context["video_adapter"] = str(context.get("video_adapter", context.get("gpu", "unknown")))
	context["render_scale"] = context.get("render_scale", 1.0)
	context["preset"] = context.get("preset", "default")
	context["environment"] = str(context.get("environment", "unknown"))
	context["seed"] = context.get("seed", 0)
	started_at_utc = Time.get_datetime_string_from_system(true, true)
	root_path = _resolve_directory(str(config.get("evidence_root", "res://.godot_user/visual_runs/current/%s" % suite_id)))
	DirAccess.make_dir_recursive_absolute(root_path)
	DirAccess.make_dir_recursive_absolute(root_path.path_join("artifacts"))
	DirAccess.make_dir_recursive_absolute(root_path.path_join("telemetry"))
	DirAccess.make_dir_recursive_absolute(root_path.path_join("diffs"))
	DirAccess.make_dir_recursive_absolute(root_path.path_join("logs"))
	catalog = _load_catalog(catalog_path)


func register_scenario(scenario_id: String, metadata: Dictionary = {}) -> Dictionary:
	var definition := _catalog_entry(scenario_id)
	var scenario_metadata := normalize(metadata) as Dictionary
	for transient_key: String in ["artifact_filename", "frame_index", "time_s", "sample_count", "capture_kind"]:
		scenario_metadata.erase(transient_key)
	definition.merge(scenario_metadata, true)
	definition["id"] = scenario_id
	if not definition.has("suite"):
		definition["suite"] = suite_id
	scenarios[scenario_id] = definition
	var prompts: Array = definition.get("human_review", []) as Array
	for prompt_variant: Variant in prompts:
		var prompt := str(prompt_variant)
		var review_id := "%s:%s" % [scenario_id, prompt]
		if not _has_review_item(review_id):
			review_items.append({
				"id": review_id,
				"scenario_id": scenario_id,
				"prompt": prompt,
				"status": "needs_review",
			})
	return definition


func capture_viewport(scenario_id: String, role: String, viewport: Viewport, metadata: Dictionary = {}) -> String:
	if viewport == null or viewport.get_texture() == null:
		record_check("artifact:%s:%s" % [scenario_id, role], "capture", "missing", null, null, "Viewport texture was unavailable")
		return ""
	RenderingServer.force_draw(true)
	var image := viewport.get_texture().get_image()
	return capture_image(scenario_id, role, image, metadata)


func capture_image(scenario_id: String, role: String, image: Image, metadata: Dictionary = {}) -> String:
	register_scenario(scenario_id, metadata)
	if image == null or image.is_empty():
		record_check("artifact:%s:%s" % [scenario_id, role], "capture", "missing", null, null, "Viewport image was empty")
		return ""
	var output := image
	if output.get_width() != capture_size.x or output.get_height() != capture_size.y:
		output = output.duplicate()
		output.resize(capture_size.x, capture_size.y, Image.INTERPOLATE_BILINEAR)
	var filename := str(metadata.get("artifact_filename", ""))
	if filename.is_empty():
		filename = "%s.png" % _safe_name(scenario_id)
	filename = _safe_filename(filename, "%s.png" % _safe_name(scenario_id))
	var relative_path := "artifacts/%s/%s" % [_safe_name(role), filename]
	var absolute_path := root_path.path_join(relative_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var error := output.save_png(absolute_path)
	if error != OK:
		record_check("artifact:%s:%s" % [scenario_id, role], "capture", "fail", error, OK, error_string(error))
		return ""
	var artifact := {
		"id": "%s:%s" % [scenario_id, role],
		"scenario_id": scenario_id,
		"role": role,
		"path": relative_path.replace("\\", "/"),
		"width": output.get_width(),
		"height": output.get_height(),
		"format": "png",
		"metadata": normalize(metadata),
	}
	_register_artifact(artifact)
	record_check("artifact:%s:%s" % [scenario_id, role], "capture", "pass", {"width": output.get_width(), "height": output.get_height()}, {"width": capture_size.x, "height": capture_size.y}, "Capture written")
	return absolute_path


func register_file_artifact(scenario_id: String, role: String, absolute_path: String, metadata: Dictionary = {}) -> String:
	register_scenario(scenario_id, metadata)
	var resolved := _resolve_file(absolute_path)
	if not FileAccess.file_exists(resolved):
		record_check("artifact:%s:%s" % [scenario_id, role], "file", "missing", null, null, "Artifact file was not produced: %s" % resolved)
		return ""
	var relative := _relative_path(resolved)
	if relative.is_empty():
		record_check("artifact:%s:%s" % [scenario_id, role], "file", "fail", null, null, "Artifact escaped evidence root: %s" % resolved)
		return ""
	_register_artifact({
		"id": "%s:%s" % [scenario_id, role],
		"scenario_id": scenario_id,
		"role": role,
		"path": relative,
		"format": resolved.get_extension().to_lower(),
		"metadata": normalize(metadata),
	})
	return resolved


func write_json_artifact(scenario_id: String, role: String, filename: String, payload: Variant, metadata: Dictionary = {}) -> String:
	register_scenario(scenario_id, metadata)
	var safe_filename := _safe_filename(filename, "%s.json" % _safe_name(scenario_id))
	var relative_path := "telemetry/%s/%s" % [_safe_name(scenario_id), safe_filename]
	var absolute_path := root_path.path_join(relative_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		record_check("artifact:%s:%s" % [scenario_id, role], "telemetry", "fail", null, null, "Could not open telemetry artifact: %s" % absolute_path)
		return ""
	file.store_string(JSON.stringify(normalize(payload), "\t"))
	file.close()
	_register_artifact({
		"id": "%s:%s" % [scenario_id, role],
		"scenario_id": scenario_id,
		"role": role,
		"path": relative_path.replace("\\", "/"),
		"format": "json",
		"metadata": normalize(metadata),
	})
	return absolute_path


func record_sample(scenario_id: String, payload: Variant) -> void:
	register_scenario(scenario_id)
	if not samples.has(scenario_id):
		samples[scenario_id] = []
	var rows: Array = samples[scenario_id] as Array
	rows.append(normalize(payload))


func record_check(check_id: String, kind: String, status: String, value: Variant = null, threshold: Variant = null, message: String = "") -> void:
	var normalized_status := status if VALID_STATUSES.has(status) else "fail"
	for existing: Dictionary in checks:
		if str(existing.get("id", "")) == check_id:
			existing["kind"] = kind
			existing["status"] = normalized_status
			existing["value"] = normalize(value)
			existing["threshold"] = normalize(threshold)
			existing["message"] = message
			return
	checks.append({
		"id": check_id,
		"kind": kind,
		"status": normalized_status,
		"value": normalize(value),
		"threshold": normalize(threshold),
		"message": message,
	})


func add_review_item(review_id: String, scenario_id: String, prompt: String, artifact_roles: Array[String] = []) -> void:
	if _has_review_item(review_id):
		return
	review_items.append({
		"id": review_id,
		"scenario_id": scenario_id,
		"prompt": prompt,
		"artifact_roles": artifact_roles,
		"status": "needs_review",
	})


func finish(exit_code: int = 0) -> Dictionary:
	if finished:
		return _read_manifest()
	finished = true
	var telemetry_entries: Array[Dictionary] = []
	var ordered_sample_ids: Array[String] = []
	for scenario_id: String in samples.keys():
		ordered_sample_ids.append(scenario_id)
	ordered_sample_ids.sort()
	for scenario_id: String in ordered_sample_ids:
		var telemetry_path := write_json_artifact(
			scenario_id,
			"telemetry",
			"samples.json",
			{"schema_version": SCHEMA_VERSION, "scenario_id": scenario_id, "samples": samples[scenario_id]},
			{"sample_count": (samples[scenario_id] as Array).size()}
		)
		telemetry_entries.append({"scenario_id": scenario_id, "path": _relative_path(telemetry_path), "sample_count": (samples[scenario_id] as Array).size()})
	var ordered_scenarios: Array[Dictionary] = []
	var scenario_ids: Array[String] = []
	for scenario_id: String in scenarios.keys():
		scenario_ids.append(scenario_id)
	scenario_ids.sort()
	for scenario_id: String in scenario_ids:
		ordered_scenarios.append(scenarios[scenario_id])
	var ordered_artifacts := artifacts.duplicate(true)
	ordered_artifacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("path", "")) < str(b.get("path", "")))
	var ordered_checks := checks.duplicate(true)
	ordered_checks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	var status := "pass" if exit_code == 0 and not _has_failed_check(ordered_checks) else "fail"
	var manifest := {
		"schema_version": SCHEMA_VERSION,
		"suite": suite_id,
		"started_at_utc": started_at_utc,
		"finished_at_utc": Time.get_datetime_string_from_system(true, true),
		"status": status,
		"exit_code": exit_code,
		"context": normalize(context),
		"scenarios": ordered_scenarios,
		"artifacts": ordered_artifacts,
		"telemetry": telemetry_entries,
		"checks": ordered_checks,
		"review_items": review_items,
		"errors": errors,
	}
	var manifest_path := root_path.path_join("visual_run.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		errors.append("Could not write suite manifest: %s" % manifest_path)
		return manifest
	file.store_string(JSON.stringify(normalize(manifest), "\t"))
	file.close()
	return manifest


func get_root_path() -> String:
	return root_path


func _register_artifact(artifact: Dictionary) -> void:
	var artifact_path := root_path.path_join(str(artifact.get("path", "")))
	if FileAccess.file_exists(artifact_path):
		artifact["bytes"] = FileAccess.get_file_as_bytes(artifact_path).size()
		artifact["sha256"] = _sha256_file(artifact_path)
	for existing: Dictionary in artifacts:
		if str(existing.get("id", "")) == str(artifact.get("id", "")):
			existing.merge(artifact, true)
			return
	artifacts.append(artifact)


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var hashing := HashingContext.new()
	var start_error := hashing.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		file.close()
		return ""
	while not file.eof_reached():
		var chunk := file.get_buffer(1024 * 1024)
		if chunk.is_empty():
			break
		hashing.update(chunk)
	file.close()
	return hashing.finish().hex_encode()


func _catalog_entry(scenario_id: String) -> Dictionary:
	var entries: Array = catalog.get("scenarios", []) as Array
	for entry_variant: Variant in entries:
		if entry_variant is Dictionary and str((entry_variant as Dictionary).get("id", "")) == scenario_id:
			return (entry_variant as Dictionary).duplicate(true)
	var templates: Array = catalog.get("templates", []) as Array
	for template_variant: Variant in templates:
		if template_variant is Dictionary:
			var prefix := str((template_variant as Dictionary).get("id_prefix", ""))
			if not prefix.is_empty() and scenario_id.begins_with(prefix):
				return (template_variant as Dictionary).duplicate(true)
	return {"id": scenario_id, "suite": suite_id, "human_review": []}


func _load_catalog(path: String) -> Dictionary:
	var resolved := path
	if path.begins_with("res://"):
		resolved = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(resolved):
		errors.append("Scenario catalog is unavailable: %s" % path)
		return {}
	var file := FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		errors.append("Scenario catalog could not be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		errors.append("Scenario catalog is not a JSON object: %s" % path)
		return {}
	return parsed as Dictionary


func _read_manifest() -> Dictionary:
	var path := root_path.path_join("visual_run.json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _has_review_item(review_id: String) -> bool:
	for item: Dictionary in review_items:
		if str(item.get("id", "")) == review_id:
			return true
	return false


func _has_failed_check(values: Array[Dictionary]) -> bool:
	for check: Dictionary in values:
		if str(check.get("status", "")) in ["fail", "missing"]:
			return true
	return false


func _resolve_directory(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	var fallback := ProjectSettings.globalize_path("res://.godot_user/visual_runs/current/%s" % suite_id)
	if normalized.is_empty() or ".." in normalized:
		errors.append("Evidence root was empty or attempted traversal: %s" % path)
		return fallback
	var resolved := ""
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(normalized)
	elif _is_absolute_path(normalized):
		resolved = normalized
	else:
		resolved = ProjectSettings.globalize_path("res://" + normalized.trim_prefix("/"))
	var project_evidence_root := ProjectSettings.globalize_path("res://.godot_user")
	var user_root := ProjectSettings.globalize_path("user://")
	if not _path_within(resolved, project_evidence_root) and not _path_within(resolved, user_root):
		errors.append("Evidence root must be under .godot_user or user://: %s" % path)
		return fallback
	return resolved


func _resolve_file(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized)
	return normalized


func _relative_path(path: String) -> String:
	var root := root_path.replace("\\", "/").trim_suffix("/")
	var candidate := path.replace("\\", "/")
	if not _path_within(candidate, root):
		return ""
	return candidate.substr(root.length() + 1)


func _path_within(candidate_path: String, parent_path: String) -> bool:
	var candidate := candidate_path.replace("\\", "/").trim_suffix("/").to_lower()
	var parent := parent_path.replace("\\", "/").trim_suffix("/").to_lower()
	return candidate == parent or candidate.begins_with(parent + "/")


func _is_absolute_path(path: String) -> bool:
	return path.begins_with("/") or (path.length() >= 3 and path[1] == ":" and path[2] == "/")


func _safe_name(value: String) -> String:
	var result := value.to_lower()
	for character: String in ["/", "\\", ":", " ", "#", "?", "&", "=", "|"]:
		result = result.replace(character, "_")
	return result


func _safe_filename(value: String, fallback: String) -> String:
	var normalized := value.strip_edges().replace("\\", "/")
	if normalized.is_empty() or normalized.begins_with("/") or ".." in normalized or normalized.contains("/"):
		return fallback
	return normalized


static func _normalize_value(value: Variant) -> Variant:
	if value == null:
		return null
	if value is Transform3D:
		var transform_3d := value as Transform3D
		return {
			"basis": [
				_normalize_value(transform_3d.basis.x),
				_normalize_value(transform_3d.basis.y),
				_normalize_value(transform_3d.basis.z),
			],
			"origin_m": _normalize_value(transform_3d.origin),
		}
	if value is Transform2D:
		var transform_2d := value as Transform2D
		return {
			"basis": [
				_normalize_value(transform_2d.x),
				_normalize_value(transform_2d.y),
			],
			"origin_m": _normalize_value(transform_2d.origin),
		}
	if value is Basis:
		var basis := value as Basis
		return [
			_normalize_value(basis.x),
			_normalize_value(basis.y),
			_normalize_value(basis.z),
		]
	if value is Quaternion:
		var quaternion := value as Quaternion
		return [quaternion.x, quaternion.y, quaternion.z, quaternion.w]
	if value is Vector2:
		var vector_2 := value as Vector2
		return [vector_2.x, vector_2.y]
	if value is Vector3:
		var vector_3 := value as Vector3
		return [vector_3.x, vector_3.y, vector_3.z]
	if value is Vector4:
		var vector_4 := value as Vector4
		return [vector_4.x, vector_4.y, vector_4.z, vector_4.w]
	if value is Color:
		var color := value as Color
		return [color.r, color.g, color.b, color.a]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			result[str(key)] = _normalize_value((value as Dictionary)[key])
		return result
	if value is Array:
		var result_array: Array = []
		for item: Variant in value as Array:
			result_array.append(_normalize_value(item))
		return result_array
	if value is PackedStringArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedColorArray:
		var packed_array: Array = []
		for item: Variant in value:
			packed_array.append(_normalize_value(item))
		return packed_array
	return value
