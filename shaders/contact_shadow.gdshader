shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled, unshaded;

uniform vec4 shadow_color : source_color = vec4(0.08, 0.12, 0.18, 1.0);
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.42;

varying vec2 plane_uv;

void vertex() {
	plane_uv = UV;
}

void fragment() {
	vec2 centered = plane_uv * 2.0 - 1.0;
	float dist = length(centered);
	float radial = 1.0 - smoothstep(0.18, 0.58, dist);
	// Soften edge further for restrained contact shadow.
	float feather = 1.0 - smoothstep(0.35, 0.62, dist);
	float alpha = radial * feather * shadow_opacity * COLOR.a;
	ALBEDO = shadow_color.rgb;
	ALPHA = alpha;
}
