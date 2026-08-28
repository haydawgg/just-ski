shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/snow_common.gdshaderinc"

uniform float sparkle_amount : hint_range(0.0, 1.0) = 0.55;
uniform float sparkle_density : hint_range(0.8, 0.999) = 0.975;
uniform float subsurface_strength : hint_range(0.0, 0.5) = 0.18;
uniform vec3 transmittance_color : source_color = vec3(0.55, 0.72, 0.9);

void vertex() {
	// Godot only allows varying writes directly from vertex(), not from helpers.
	snow_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	snow_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 surface_albedo;
	vec3 surface_normal_view;
	float surface_roughness;
	float surface_translucency;
	float detail_visibility;
	snow_surface(INV_VIEW_MATRIX[3].xyz, mat3(VIEW_MATRIX), surface_albedo, surface_normal_view, surface_roughness, surface_translucency, detail_visibility);
	float crystal_mask = snow_crystal_mask(detail_visibility, sparkle_amount, sparkle_density);

	ALBEDO = surface_albedo;
	NORMAL = surface_normal_view;
	ROUGHNESS = clamp(surface_roughness - crystal_mask * 0.3, 0.2, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	CLEARCOAT = crystal_mask;
	CLEARCOAT_ROUGHNESS = mix(0.16, 0.035, crystal_mask);
	SSS_STRENGTH = subsurface_strength * mix(0.45, surface_translucency, detail_visibility);
	SSS_TRANSMITTANCE_COLOR = vec4(transmittance_color, 1.0);
	SSS_TRANSMITTANCE_DEPTH = 0.25;
	SSS_TRANSMITTANCE_BOOST = 0.12;
}
