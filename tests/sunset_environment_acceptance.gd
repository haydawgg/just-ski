extends Node

var failures: Array[String] = []

@onready var resort: Node3D = $Resort

func _ready() -> void:
	for _frame: int in 150:
		await get_tree().physics_frame
	var profile := resort.get("environment_profile") as ResortEnvironmentProfile
	var world_environment := resort.get("environment") as WorldEnvironment
	var sun := resort.get("sun") as DirectionalLight3D
	if profile == null or not profile.gi_enabled:
		failures.append("Sunset scene did not select a GI-enabled environment profile")
	else:
		if profile.sun_color.g < 0.88 or profile.sun_color.b < 0.78:
			failures.append("Sunset sun is warm enough to erase neutral snow readability")
		if profile.sun_energy > 1.3 or profile.exposure > 1.0:
			failures.append("Sunset exposure budget is high enough to wash snow into a sepia field")
	if profile != null:
		if profile.sky_horizon_color.r <= profile.sky_horizon_color.b:
			failures.append("Sunset horizon palette is not warmer than its blue channel")
		if profile.sun_rotation_degrees.x > -12.0 or profile.sun_rotation_degrees.x < -40.0:
			failures.append("Sunset sun elevation %.1f degrees is outside the low-angle lighting range" % profile.sun_rotation_degrees.x)
	if world_environment == null or world_environment.environment == null:
		failures.append("Sunset scene did not create a WorldEnvironment")
	else:
		var env := world_environment.environment
		var quality_allows_gi := int(GameSettings.active.get("graphics_preset", 2)) >= 2
		if env.sdfgi_enabled != quality_allows_gi:
			failures.append("Sunset SDFGI enabled=%s did not follow profile/quality gating" % env.sdfgi_enabled)
		if env.sdfgi_bounce_feedback > 0.5:
			failures.append("Sunset SDFGI bounce feedback %.2f exceeds the safe limit" % env.sdfgi_bounce_feedback)
		if env.sdfgi_cascades < 2 or env.sdfgi_max_distance < 128.0:
			failures.append("Sunset SDFGI coverage is too small for the downhill scene")
	if sun == null or not sun.shadow_enabled:
		failures.append("Sunset scene lost its directional shadow source")
	var static_geometry := 0
	for node: Node in resort.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry != null and geometry.gi_mode == GeometryInstance3D.GI_MODE_STATIC:
			static_geometry += 1
	if static_geometry < 8:
		failures.append("Sunset scene marked only %d environment meshes for static GI" % static_geometry)
	var local_lights := resort.find_children("*", "OmniLight3D", true, false).size() + resort.find_children("*", "SpotLight3D", true, false).size()
	if local_lights > 0:
		failures.append("Sunset scene added %d local lights instead of using the sun/SDFGI setup" % local_lights)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("SUNSET_ENVIRONMENT_PASS: warm sky, low sun, static SDFGI geometry, shadows, and quality gating validated")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SUNSET_ENVIRONMENT_FAIL: " + failure)
	get_tree().quit(1)
