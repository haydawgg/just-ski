shader_type spatial;
render_mode shadows_disabled, blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The authored summit heightfield is presentation-only and deliberately sits
// outside the gameplay collision mesh. Keep its snow texture/detail treatment
// identical to the existing piste material, but avoid receiving the low-angle
// sunset shadow map that can swallow a large render-only surface.
#include "res://shaders/snow_common.gdshaderinc"

void vertex() {
	snow_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	snow_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void light() {
	// Broad snow scattering keeps grazing slopes bright while detail normals
	// still modulate the directional light. No emissive whitening is needed.
	float wrapped_diffuse = clamp((dot(NORMAL, LIGHT) + 0.45) / 1.45, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * wrapped_diffuse / PI;
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
	float broad_variation = snow_value_noise(snow_world_position.xz * max(far_macro_scale, 0.001));
	float form_value = mix(0.94, 1.06, form_light);
	float macro_value = mix(0.97, 1.03, broad_variation);
	surface_albedo *= form_value * macro_value;
	float drift_value = (snow_value_noise(snow_world_position.xz * 0.18) - 0.5) * 0.9;
	float broad_value = (broad_variation - 0.5) * 0.12;
	surface_albedo += vec3(drift_value + broad_value);
	float varied_luminance = dot(surface_albedo, vec3(0.2126, 0.7152, 0.0722));
	if (varied_luminance < 0.58) {
		surface_albedo += vec3(0.58 - varied_luminance);
	}
	ALBEDO = clamp(surface_albedo, vec3(0.0), vec3(1.0));
	NORMAL = surface_normal_view;
	SPECULAR = 0.5;
	ROUGHNESS = surface_roughness;
}
