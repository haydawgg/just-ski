shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_disabled, unshaded;

uniform vec4 shadow_color : source_color = vec4(0.08, 0.12, 0.18, 1.0);
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.42;
uniform float shadow_softness : hint_range(0.0, 1.0) = 0.2;

varying vec2 plane_uv;

void vertex() {
	plane_uv = UV;
}

void fragment() {
	vec2 centered = plane_uv * 2.0 - 1.0;
	float dist = length(centered);
	float edge_start = mix(0.58, 0.14, shadow_softness);
	float edge_end = mix(0.82, 0.96, shadow_softness);
	float footprint = 1.0 - smoothstep(edge_start, edge_end, dist);
	float alpha = footprint * shadow_opacity * COLOR.a;
	ALBEDO = shadow_color.rgb;
	ALPHA = alpha;
}
