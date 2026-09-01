shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 haze_color : source_color = vec4(0.88, 0.92, 0.96, 1.0);
uniform float haze_alpha : hint_range(0.0, 0.3) = 0.09;
uniform float haze_scale : hint_range(0.001, 0.05) = 0.008;
uniform float haze_speed : hint_range(0.0, 0.1) = 0.0;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 c = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(c);
	float b = hash12(c + vec2(1.0, 0.0));
	float c2 = hash12(c + vec2(0.0, 1.0));
	float d = hash12(c + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c2, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Subtle high-altitude variation that breaks the uniform horizon without adding fog.
	float n1 = value_noise(world_pos.xz * haze_scale);
	float n2 = value_noise(world_pos.xz * haze_scale * 2.35 + vec2(17.0, -9.0));
	float n = mix(n1, n2, 0.45);
	// Ridge-like soft clouds, very restrained.
	float cloud = smoothstep(0.48, 0.72, n);
	float alpha = cloud * haze_alpha * (0.7 + 0.3 * n);
	// Fade with distance to avoid hard edges at world bounds.
	float dist = length(world_pos.xz) / 1800.0;
	float dist_fade = 1.0 - smoothstep(0.55, 0.95, dist);
	// Fade with view angle to keep horizon soft.
	float view_fade = 1.0 - smoothstep(0.65, 0.92, abs(world_pos.y) / 400.0);
	ALBEDO = haze_color.rgb;
	ALPHA = alpha * dist_fade * view_fade;
}
