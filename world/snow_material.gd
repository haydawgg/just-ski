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

	func _init(kind: int, groom_direction: Vector2) -> void:
		surface_kind = kind
		groom_direction_world_xz = groom_direction.normalized() if groom_direction.length_squared() > 0.0001 else Vector2(0.0, -1.0)
		GameSettings.settings_applied.connect(_apply_quality)
		_apply_quality()

	func _apply_quality() -> void:
		var premium := int(GameSettings.active.get("snow_quality", 1)) == 1
		shader = SnowMaterial.PREMIUM_SHADER if premium else SnowMaterial.FAST_SHADER
		set_shader_parameter("snow_albedo_texture", SnowMaterial.ALBEDO_TEXTURE)
		set_shader_parameter("snow_detail_texture", SnowMaterial.DETAIL_TEXTURE)
		set_shader_parameter("texture_world_size", 2.0)
		set_shader_parameter("triplanar_sharpness", 4.0)
		set_shader_parameter("detail_near_distance", 20.0)
		set_shader_parameter("detail_far_distance", 60.0)
		set_shader_parameter("groom_direction_world_xz", groom_direction_world_xz)
		_apply_surface_parameters(premium)

	func _apply_surface_parameters(premium: bool) -> void:
		match surface_kind:
			SnowMaterial.Kind.PACKED:
				set_shader_parameter("snow_color", Color(0.82, 0.89, 0.95))
				set_shader_parameter("shadow_tint", Color(0.48, 0.62, 0.76))
				set_shader_parameter("roughness_base", 0.86)
				set_shader_parameter("albedo_texture_strength", 0.36)
				set_shader_parameter("normal_strength", 0.52)
				set_shader_parameter("roughness_texture_strength", 0.62)
				set_shader_parameter("macro_tint_amount", 0.045)
				set_shader_parameter("corduroy_amount", 0.22)
				set_shader_parameter("corduroy_frequency", 3.0)
				if premium:
					set_shader_parameter("sparkle_amount", 0.28)
					set_shader_parameter("sparkle_density", 0.978)
					set_shader_parameter("subsurface_strength", 0.10)
			SnowMaterial.Kind.GROOMED:
				set_shader_parameter("snow_color", Color(0.88, 0.90, 0.93))
				set_shader_parameter("shadow_tint", Color(0.62, 0.68, 0.74))
				set_shader_parameter("roughness_base", 0.70)
				set_shader_parameter("albedo_texture_strength", 0.28)
				set_shader_parameter("normal_strength", 0.34)
				set_shader_parameter("roughness_texture_strength", 0.58)
				set_shader_parameter("macro_tint_amount", 0.025)
				set_shader_parameter("corduroy_amount", 0.55)
				set_shader_parameter("corduroy_frequency", 3.6)
				if premium:
					set_shader_parameter("sparkle_amount", 0.18)
					set_shader_parameter("sparkle_density", 0.984)
					set_shader_parameter("subsurface_strength", 0.06)
			_:
				set_shader_parameter("snow_color", Color(0.94, 0.97, 1.0))
				set_shader_parameter("shadow_tint", Color(0.56, 0.71, 0.86))
				set_shader_parameter("roughness_base", 0.78)
				set_shader_parameter("albedo_texture_strength", 0.44)
				set_shader_parameter("normal_strength", 0.76)
				set_shader_parameter("roughness_texture_strength", 0.72)
				set_shader_parameter("macro_tint_amount", 0.07)
				set_shader_parameter("corduroy_amount", 0.0)
				set_shader_parameter("corduroy_frequency", 3.0)
				if premium:
					set_shader_parameter("sparkle_amount", 0.62)
					set_shader_parameter("sparkle_density", 0.96)
					set_shader_parameter("subsurface_strength", 0.18)

static func create(kind: Kind = Kind.POWDER, groom_direction_world_xz: Vector2 = Vector2(0.0, -1.0)) -> ShaderMaterial:
	return SnowMaterialInstance.new(kind, groom_direction_world_xz)
