class_name SnowMaterial
extends RefCounted

enum Kind { POWDER, PACKED, GROOMED }

const FAST_SHADER: Shader = preload("res://shaders/snow_fast.gdshader")
const PREMIUM_SHADER: Shader = preload("res://shaders/snow_premium.gdshader")
const ALBEDO_TEXTURE: Texture2D = preload("res://assets/materials/snow_02/snow_02_diff_2k.jpg")
const DETAIL_TEXTURE: Texture2D = preload("res://assets/materials/snow_02/snow_02_detail_2k.png")
const PRESENTATION: SnowPresentationProfile = preload("res://resources/materials/default_snow_presentation_profile.tres")

class SnowMaterialInstance extends ShaderMaterial:
	var surface_kind: int
	var groom_direction_world_xz: Vector2
	var feature_emphasis: float

	func _init(kind: int, groom_direction: Vector2, emphasis: float) -> void:
		surface_kind = kind
		groom_direction_world_xz = groom_direction.normalized() if groom_direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
		feature_emphasis = clampf(emphasis, 0.0, 1.0)
		GameSettings.settings_applied.connect(_apply_quality)
		_apply_quality()

	func _apply_quality() -> void:
		var premium := int(GameSettings.active.get("snow_quality", 1)) == 1
		shader = SnowMaterial.PREMIUM_SHADER if premium else SnowMaterial.FAST_SHADER
		set_shader_parameter("snow_albedo_texture", SnowMaterial.ALBEDO_TEXTURE)
		set_shader_parameter("snow_detail_texture", SnowMaterial.DETAIL_TEXTURE)
		set_shader_parameter("texture_world_size", 1.35)
		set_shader_parameter("triplanar_sharpness", 4.0)
		set_shader_parameter("detail_near_distance", SnowMaterial.PRESENTATION.detail_near_distance)
		set_shader_parameter("detail_far_distance", SnowMaterial.PRESENTATION.detail_far_distance)
		set_shader_parameter("groom_direction_world_xz", groom_direction_world_xz)
		set_shader_parameter("feature_emphasis", feature_emphasis)
		set_shader_parameter("warm_snow_tint", SnowMaterial.PRESENTATION.warm_tint)
		set_shader_parameter("cool_snow_tint", SnowMaterial.PRESENTATION.cool_tint)
		set_shader_parameter("macro_temperature_amount", SnowMaterial.PRESENTATION.temperature_amount)
		set_shader_parameter("macro_scale", SnowMaterial.PRESENTATION.medium_variation_scale)
		set_shader_parameter("far_macro_scale", SnowMaterial.PRESENTATION.broad_variation_scale)
		set_shader_parameter("form_light_direction_world_xz", SnowMaterial.PRESENTATION.form_light_direction_world_xz)
		set_shader_parameter("steepness_contrast_strength", SnowMaterial.PRESENTATION.steepness_contrast)
		set_shader_parameter("minimum_albedo_luminance", SnowMaterial.PRESENTATION.minimum_albedo_luminance)
		set_shader_parameter("feature_tint", Color(0.86, 0.9, 0.94))
		set_shader_parameter("disturbed_roughness_offset", 0.075)
		set_shader_parameter("disturbed_detail_boost", 0.15)
		_apply_surface_parameters(premium)

	func _apply_surface_parameters(premium: bool) -> void:
		match surface_kind:
			SnowMaterial.Kind.PACKED:
				set_shader_parameter("snow_color", SnowMaterial.PRESENTATION.packed_color)
				set_shader_parameter("shadow_tint", SnowMaterial.PRESENTATION.packed_shadow_tint)
				set_shader_parameter("roughness_base", SnowMaterial.PRESENTATION.packed_roughness)
				set_shader_parameter("albedo_texture_strength", 0.065)
				set_shader_parameter("normal_strength", 0.20)
				set_shader_parameter("roughness_texture_strength", 0.45)
				set_shader_parameter("macro_tint_amount", SnowMaterial.PRESENTATION.packed_medium_variation)
				set_shader_parameter("far_macro_tint_amount", SnowMaterial.PRESENTATION.packed_broad_variation)
				set_shader_parameter("macro_roughness_amount", SnowMaterial.PRESENTATION.roughness_variation)
				set_shader_parameter("slope_contrast_strength", 0.065)
				set_shader_parameter("form_contrast_strength", SnowMaterial.PRESENTATION.packed_form_contrast)
				set_shader_parameter("wind_crust_amount", 0.022)
				set_shader_parameter("corduroy_amount", 0.012)
				set_shader_parameter("corduroy_frequency", 1.65)
				if premium:
					set_shader_parameter("sparkle_amount", 0.035)
					set_shader_parameter("sparkle_density", 0.994)
					set_shader_parameter("subsurface_strength", 0.08)
			SnowMaterial.Kind.GROOMED:
				set_shader_parameter("snow_color", SnowMaterial.PRESENTATION.groomed_color)
				set_shader_parameter("shadow_tint", SnowMaterial.PRESENTATION.groomed_shadow_tint)
				set_shader_parameter("roughness_base", SnowMaterial.PRESENTATION.groomed_roughness)
				set_shader_parameter("albedo_texture_strength", 0.055)
				set_shader_parameter("normal_strength", 0.17)
				set_shader_parameter("roughness_texture_strength", 0.38)
				set_shader_parameter("macro_tint_amount", SnowMaterial.PRESENTATION.groomed_medium_variation)
				set_shader_parameter("far_macro_tint_amount", SnowMaterial.PRESENTATION.groomed_broad_variation)
				set_shader_parameter("macro_roughness_amount", SnowMaterial.PRESENTATION.roughness_variation)
				set_shader_parameter("slope_contrast_strength", 0.045)
				set_shader_parameter("form_contrast_strength", SnowMaterial.PRESENTATION.groomed_form_contrast)
				set_shader_parameter("wind_crust_amount", 0.012)
				set_shader_parameter("corduroy_amount", 0.018)
				set_shader_parameter("corduroy_frequency", 1.8)
				if premium:
					set_shader_parameter("sparkle_amount", 0.025)
					set_shader_parameter("sparkle_density", 0.995)
					set_shader_parameter("subsurface_strength", 0.05)
			_:
				set_shader_parameter("snow_color", SnowMaterial.PRESENTATION.powder_color)
				set_shader_parameter("shadow_tint", SnowMaterial.PRESENTATION.powder_shadow_tint)
				set_shader_parameter("roughness_base", SnowMaterial.PRESENTATION.powder_roughness)
				set_shader_parameter("albedo_texture_strength", 0.08)
				set_shader_parameter("normal_strength", 0.28)
				set_shader_parameter("roughness_texture_strength", 0.36)
				set_shader_parameter("macro_tint_amount", SnowMaterial.PRESENTATION.powder_medium_variation)
				set_shader_parameter("far_macro_tint_amount", SnowMaterial.PRESENTATION.powder_broad_variation)
				set_shader_parameter("macro_roughness_amount", SnowMaterial.PRESENTATION.roughness_variation)
				set_shader_parameter("slope_contrast_strength", 0.085)
				set_shader_parameter("form_contrast_strength", SnowMaterial.PRESENTATION.powder_form_contrast)
				set_shader_parameter("wind_crust_amount", 0.03)
				set_shader_parameter("corduroy_amount", 0.0)
				set_shader_parameter("corduroy_frequency", 3.0)
				if premium:
					set_shader_parameter("sparkle_amount", 0.05)
					set_shader_parameter("sparkle_density", 0.992)
					set_shader_parameter("subsurface_strength", 0.14)

static func create(kind: Kind = Kind.POWDER, groom_direction_world_xz: Vector2 = Vector2(0.0, -1.0), feature_emphasis: float = 0.0) -> ShaderMaterial:
	return SnowMaterialInstance.new(kind, groom_direction_world_xz, feature_emphasis)
