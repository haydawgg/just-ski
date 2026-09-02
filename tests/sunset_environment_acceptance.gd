extends Node

const ResortModule := preload("res://world/resort.gd")

var failures: Array[String] = []

@onready var resort: Node3D = $Resort

func _ready() -> void:
	for _frame: int in 150:
		await get_tree().physics_frame
	var profile := resort.get("environment_profile") as ResortEnvironmentProfile
	var world_environment := resort.get("environment") as WorldEnvironment
	var sun := resort.get("sun") as DirectionalLight3D
	var active_environment: Environment = null
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
		active_environment = env
		var expected_gi: bool = bool(resort.call("effective_gi_enabled"))
		if env.sdfgi_enabled != expected_gi:
			failures.append("Sunset SDFGI enabled=%s did not follow profile/user/preset gating (expected %s)" % [env.sdfgi_enabled, expected_gi])
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
	_test_gi_policy(resort, active_environment)
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("SUNSET_ENVIRONMENT_PASS: warm sky, low sun, static SDFGI geometry, shadows, and quality gating validated")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("SUNSET_ENVIRONMENT_FAIL: " + failure)
	get_tree().quit(1)

func _test_gi_policy(sunset_resort: Node3D, env: Environment) -> void:
	var sunset_profile := sunset_resort.get("environment_profile") as ResortEnvironmentProfile
	var default_profile := preload("res://resources/environment/default_resort_environment_profile.tres") as ResortEnvironmentProfile
	var golden_profile := preload("res://resources/environment/golden_hour_resort_environment_profile.tres") as ResortEnvironmentProfile
	if ResortModule.profile_for_preset(0) != default_profile:
		failures.append("Day setting did not resolve to the authored daytime profile")
	if ResortModule.profile_for_preset(1) != golden_profile:
		failures.append("Golden Hour setting did not resolve to its authored profile")
	if ResortModule.profile_for_preset(2) != sunset_profile:
		failures.append("Sunset setting did not resolve to the authored sunset profile")
	if bool(sunset_resort.get("follow_environment_setting")):
		failures.append("Dedicated sunset scene no longer keeps its authored QA profile")
	if ResortModule.resolve_effective_gi(default_profile, true, 3):
		failures.append("A GI-disabled environment profile incorrectly enabled GI")
	if not ResortModule.resolve_effective_gi(sunset_profile, true, 2):
		failures.append("A GI-capable profile/high preset combination did not allow GI")
	if ResortModule.resolve_effective_gi(sunset_profile, true, 1):
		failures.append("A Medium preset incorrectly allowed GI")
	if env == null:
		return
	var original_active := GameSettings.active.duplicate(true)
	var original_pending := GameSettings.pending.duplicate(true)
	var original_environment_gi := env.sdfgi_enabled
	GameSettings.begin_edit()
	GameSettings.set_pending("gi_enabled", not bool(original_active["gi_enabled"]))
	if env.sdfgi_enabled != original_environment_gi:
		failures.append("Staging GI changed the active environment before Apply")
	GameSettings.cancel_pending()
	if bool(GameSettings.pending["gi_enabled"]) != bool(original_active["gi_enabled"]):
		failures.append("Cancel did not restore the pending GI value")
	GameSettings.begin_edit()
	GameSettings.set_pending("graphics_preset", 1)
	GameSettings.apply_pending()
	if env.sdfgi_enabled:
		failures.append("Applying a GI-forbidden preset left SDFGI enabled")
	GameSettings.begin_edit()
	GameSettings.apply_preset(2)
	GameSettings.apply_pending()
	if not env.sdfgi_enabled:
		failures.append("Applying GI with a capable profile and preset did not enable SDFGI")
	var active_before_save_failure := GameSettings.active.duplicate(true)
	var save_error := GameSettings.save_settings("res://tests")
	if save_error == OK or not env.sdfgi_enabled or GameSettings.active != active_before_save_failure:
		failures.append("A GI save failure did not preserve the applied runtime state")
	GameSettings.active = original_active
	GameSettings.pending = original_pending
	GameSettings.apply_pending()
