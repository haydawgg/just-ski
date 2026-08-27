class_name SnowMaterial
extends RefCounted

enum Kind { POWDER, PACKED, GROOMED }

const SHADER: Shader = preload("res://shaders/snow.gdshader")

static func create(kind: Kind = Kind.POWDER) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	match kind:
		Kind.PACKED:
			material.set_shader_parameter("snow_color", Color(0.82, 0.89, 0.95))
			material.set_shader_parameter("shadow_tint", Color(0.48, 0.62, 0.76))
			material.set_shader_parameter("grain_scale", 16.0)
			material.set_shader_parameter("dune_scale", 0.16)
			material.set_shader_parameter("dune_height", 0.32)
			material.set_shader_parameter("sparkle_amount", 0.28)
			material.set_shader_parameter("sparkle_density", 0.978)
			material.set_shader_parameter("roughness_base", 0.82)
			material.set_shader_parameter("corduroy_amount", 0.22)
			material.set_shader_parameter("corduroy_freq", 11.0)
			material.set_shader_parameter("subsurface", 0.28)
		Kind.GROOMED:
			material.set_shader_parameter("snow_color", Color(0.88, 0.9, 0.93))
			material.set_shader_parameter("shadow_tint", Color(0.62, 0.68, 0.74))
			material.set_shader_parameter("grain_scale", 18.0)
			material.set_shader_parameter("dune_scale", 0.2)
			material.set_shader_parameter("dune_height", 0.22)
			material.set_shader_parameter("sparkle_amount", 0.18)
			material.set_shader_parameter("sparkle_density", 0.984)
			material.set_shader_parameter("roughness_base", 0.7)
			material.set_shader_parameter("corduroy_amount", 0.55)
			material.set_shader_parameter("corduroy_freq", 16.0)
			material.set_shader_parameter("subsurface", 0.18)
		_:
			material.set_shader_parameter("snow_color", Color(0.94, 0.97, 1.0))
			material.set_shader_parameter("shadow_tint", Color(0.56, 0.71, 0.86))
			material.set_shader_parameter("grain_scale", 11.0)
			material.set_shader_parameter("dune_scale", 0.09)
			material.set_shader_parameter("dune_height", 0.7)
			material.set_shader_parameter("sparkle_amount", 0.62)
			material.set_shader_parameter("sparkle_density", 0.96)
			material.set_shader_parameter("roughness_base", 0.72)
			material.set_shader_parameter("corduroy_amount", 0.0)
			material.set_shader_parameter("subsurface", 0.4)
	return material
