class_name SnowMaterial
extends RefCounted

enum Kind { POWDER, PACKED, GROOMED }

const FAST_SHADER: Shader = preload("res://shaders/snow_fast.gdshader")
const PREMIUM_SHADER: Shader = preload("res://shaders/snow_premium.gdshader")
const ALBEDO_TEXTURE: Texture2D = preload("res://assets/materials/snow_02/snow_02_diff_2k.jpg")
const DETAIL_TEXTURE: Texture2D = preload("res://assets/materials/snow_02/snow_02_detail_2k.png")

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
		set_shader_parameter("detail_near_distance", 18.0)
		set_shader_parameter("detail_far_distance", 58.0)
		set_shader_parameter("groom_direction_world_xz", groom_direction_world_xz)
		set_shader_parameter("feature_emphasis", feature_emphasis)
		set_shader_parameter("warm_snow_tint", Color(1.0, 0.982, 0.948))
		set_shader_parameter("cool_snow_tint", Color(0.958, 0.982, 1.0))
		set_shader_parameter("feature_tint", Color(0.86, 0.9, 0.94))
		set_shader_parameter("disturbed_roughness_offset", 0.075)
		set_shader_parameter("disturbed_detail_boost", 0.15)
		_apply_surface_parameters(premium)

	func _apply_surface_parameters(premium: bool) -> void:
		match surface_kind:
			SnowMaterial.Kind.PACKED:
				set_shader_parameter("snow_color", Color(0.925, 0.945, 0.96))
				set_shader_parameter("shadow_tint", Color(0.56, 0.66, 0.76))
				set_shader_parameter("roughness_base", 0.76)
				set_shader_parameter("albedo_texture_strength", 0.10)
				set_shader_parameter("normal_strength", 0.28)
				set_shader_parameter("roughness_texture_strength", 0.45)
				set_shader_parameter("macro_tint_amount", 0.055)
				set_shader_parameter("far_macro_tint_amount", 0.075)
				set_shader_parameter("macro_temperature_amount", 0.85)
				set_shader_parameter("macro_roughness_amount", 0.10)
				set_shader_parameter("slope_contrast_strength", 0.065)
				set_shader_parameter("wind_crust_amount", 0.022)
				set_shader_parameter("corduroy_amount", 0.12)
				set_shader_parameter("corduroy_frequency", 3.0)
				if premium:
					set_shader_parameter("sparkle_amount", 0.035)
					set_shader_parameter("sparkle_density", 0.994)
					set_shader_parameter("subsurface_strength", 0.08)
			SnowMaterial.Kind.GROOMED:
				set_shader_parameter("snow_color", Color(0.94, 0.955, 0.965))
				set_shader_parameter("shadow_tint", Color(0.62, 0.70, 0.78))
				set_shader_parameter("roughness_base", 0.82)
				set_shader_parameter("albedo_texture_strength", 0.10)
				set_shader_parameter("normal_strength", 0.24)
				set_shader_parameter("roughness_texture_strength", 0.38)
				set_shader_parameter("macro_tint_amount", 0.045)
				set_shader_parameter("far_macro_tint_amount", 0.075)
				set_shader_parameter("macro_temperature_amount", 0.92)
				set_shader_parameter("macro_roughness_amount", 0.08)
				set_shader_parameter("slope_contrast_strength", 0.045)
				set_shader_parameter("wind_crust_amount", 0.012)
				set_shader_parameter("corduroy_amount", 0.16)
				set_shader_parameter("corduroy_frequency", 2.8)
				if premium:
					set_shader_parameter("sparkle_amount", 0.025)
					set_shader_parameter("sparkle_density", 0.995)
					set_shader_parameter("subsurface_strength", 0.05)
			_:
				set_shader_parameter("snow_color", Color(0.955, 0.97, 0.985))
				set_shader_parameter("shadow_tint", Color(0.60, 0.70, 0.80))
				set_shader_parameter("roughness_base", 0.88)
				set_shader_parameter("albedo_texture_strength", 0.12)
				set_shader_parameter("normal_strength", 0.38)
				set_shader_parameter("roughness_texture_strength", 0.36)
				set_shader_parameter("macro_tint_amount", 0.075)
				set_shader_parameter("far_macro_tint_amount", 0.10)
				set_shader_parameter("macro_temperature_amount", 1.0)
				set_shader_parameter("macro_roughness_amount", 0.14)
				set_shader_parameter("slope_contrast_strength", 0.085)
				set_shader_parameter("wind_crust_amount", 0.03)
				set_shader_parameter("corduroy_amount", 0.0)
				set_shader_parameter("corduroy_frequency", 3.0)
				if premium:
					set_shader_parameter("sparkle_amount", 0.05)
					set_shader_parameter("sparkle_density", 0.992)
					set_shader_parameter("subsurface_strength", 0.14)

static func create(kind: Kind = Kind.POWDER, groom_direction_world_xz: Vector2 = Vector2(0.0, -1.0), feature_emphasis: float = 0.0) -> ShaderMaterial:
	return SnowMaterialInstance.new(kind, groom_direction_world_xz, feature_emphasis)
