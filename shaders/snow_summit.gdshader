shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// The authored summit heightfield is presentation-only and deliberately sits
// outside the gameplay collision mesh. Keep its snow texture/detail treatment
// identical to the existing piste material, but avoid receiving the low-angle
// sunset shadow map that can swallow a large render-only surface.
#include "res://shaders/snow_common.gdshaderinc"

void vertex() {
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
	vec3 form_direction = normalize(vec3(form_light_direction_world_xz.x, 0.82, form_light_direction_world_xz.y));
	float form_light = clamp(dot(normalize(snow_world_normal), form_direction), 0.0, 1.0);
	float medium_variation = snow_value_noise(snow_world_position.xz * max(macro_scale, 0.001));
	float broad_variation = snow_value_noise(snow_world_position.xz * max(far_macro_scale, 0.001));
	float form_value = mix(0.94, 1.06, form_light);
	float macro_value = mix(0.97, 1.03, broad_variation);
	float medium_value = mix(0.98, 1.02, medium_variation);
	surface_albedo *= form_value * macro_value * medium_value;
	ALBEDO = clamp(surface_albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = surface_roughness;
}
