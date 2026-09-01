shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// The authored summit heightfield is presentation-only and deliberately sits
// outside the gameplay collision mesh. Keep its snow texture/detail treatment
// identical to the existing piste material, but avoid receiving the low-angle
// sunset shadow map that can swallow a large render-only surface.
#include "res://shaders/snow_common.gdshaderinc"

const float SUMMIT_MACRO_FREQUENCY_MULTIPLIER = 100.0;
const float SUMMIT_FINE_FREQUENCY_MULTIPLIER = 130.0;

void vertex() {
	// Match the production snow material's world-space inputs so all texture
	// and macro parameters remain shared between lit and render-only surfaces.
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
	// Keep an authored form gradient in the unshaded path. It gives the stylized
	// heightfield readable shoulders and bowls without re-entering the
	// problematic low-angle shadow receiver path.
	vec3 form_direction = normalize(vec3(form_light_direction_world_xz.x, 0.82, form_light_direction_world_xz.y));
	float form_light = clamp(dot(normalize(snow_world_normal), form_direction), 0.0, 1.0);
	float broad_variation = snow_value_noise(snow_world_position.xz * max(far_macro_scale * SUMMIT_MACRO_FREQUENCY_MULTIPLIER, 0.001));
	// The lit snow shader gets value separation from direct light and shadowing.
	// This shadow-safe path needs an equivalent seeded world-space signal. The
	// profile scale is intentionally remapped because the near camera footprint
	// spans only a few meters and would otherwise sample one nearly constant cell.
	float summit_form_value = mix(0.84, 1.12, form_light);
	float summit_macro_value = mix(0.1, 2.3, broad_variation);
	float summit_fine_variation = snow_value_noise(snow_world_position.xz * max(far_macro_scale * SUMMIT_FINE_FREQUENCY_MULTIPLIER, 0.001) + vec2(37.0, -19.0));
	summit_macro_value *= mix(0.86, 1.14, summit_fine_variation);
	surface_albedo *= summit_form_value * summit_macro_value;
	float summit_luminance = dot(surface_albedo, vec3(0.2126, 0.7152, 0.0722));
	if (summit_luminance < 0.54) {
		surface_albedo *= 0.54 / max(summit_luminance, 0.001);
	}
	ALBEDO = clamp(surface_albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = surface_roughness;
}
