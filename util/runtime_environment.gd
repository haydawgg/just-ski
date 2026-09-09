class_name RuntimeEnvironment
extends RefCounted

## Runtime capability helpers shared by gameplay, profiling, and visual tests.
## Godot's console renderer identifies itself as a headless DisplayServer even
## on builds where OS.has_feature("headless") is not set.

static func is_headless() -> bool:
	return OS.has_feature("headless") or DisplayServer.get_name().to_lower() == "headless"
