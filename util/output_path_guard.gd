class_name OutputPathGuard
extends RefCounted

## Restricts tool/test write paths to generated and user-data trees so a CLI
## argument cannot overwrite project sources.

const ALLOWED_PREFIXES: Array[String] = [
	"res://world/generated/",
	"res://.godot_user/",
	"user://",
]


static func sanitize(path: String, allowed_extensions: PackedStringArray, fallback: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty() or ".." in normalized:
		return fallback
	var allowed := false
	for prefix: String in ALLOWED_PREFIXES:
		if normalized.begins_with(prefix):
			allowed = true
			break
	if not allowed:
		return fallback
	if not allowed_extensions.is_empty():
		var extension := "." + normalized.get_extension().to_lower()
		var extension_ok := false
		for allowed_extension: String in allowed_extensions:
			if extension == allowed_extension:
				extension_ok = true
				break
		if not extension_ok:
			return fallback
	return normalized


static func parse_finite_float(text: String, fallback: float, minimum: float, maximum: float) -> float:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or not trimmed.is_valid_float():
		return fallback
	var value := float(trimmed)
	if not is_finite(value):
		return fallback
	return clampf(value, minimum, maximum)


static func parse_int_range(text: String, fallback: int, minimum: int, maximum: int) -> int:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or not trimmed.is_valid_int():
		return fallback
	return clampi(int(trimmed), minimum, maximum)
