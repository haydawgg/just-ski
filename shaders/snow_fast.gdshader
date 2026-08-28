shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/snow_common.gdshaderinc"

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

	ALBEDO = surface_albedo;
	NORMAL = surface_normal_view;
	ROUGHNESS = clamp(surface_roughness, 0.28, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
