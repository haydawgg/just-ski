shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 snow_color : source_color = vec3(0.93, 0.96, 0.99);
uniform vec3 shadow_tint : source_color = vec3(0.58, 0.71, 0.84);
uniform vec3 sparkle_color : source_color = vec3(0.92, 0.97, 1.0);
uniform float grain_scale : hint_range(1.0, 40.0) = 12.0;
uniform float dune_scale : hint_range(0.02, 1.0) = 0.11;
uniform float dune_height : hint_range(0.0, 2.0) = 0.55;
uniform float sparkle_amount : hint_range(0.0, 1.0) = 0.55;
uniform float sparkle_density : hint_range(0.8, 0.995) = 0.965;
uniform float roughness_base : hint_range(0.2, 1.0) = 0.74;
uniform float corduroy_amount : hint_range(0.0, 1.0) = 0.0;
uniform float corduroy_freq : hint_range(1.0, 40.0) = 14.0;
uniform float subsurface : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amp * noise(p);
		p = p * 2.07 + 17.2;
		amp *= 0.5;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 nrm = normalize(world_normal);
	vec2 uv = world_pos.xz;
	float dunes = fbm(uv * dune_scale);
	float grain = fbm(uv * grain_scale);
	float cord = sin(world_pos.z * corduroy_freq + dunes * 1.8) * corduroy_amount;
	float micro = grain * 0.22 + dunes * 0.45 + cord * 0.18;

	vec3 bump = vec3(dFdx(micro), 0.0, dFdy(micro)) * dune_height * 3.5;
	NORMAL = normalize(NORMAL - vec3(bump.x, 0.0, bump.z));

	float sky_term = clamp(nrm.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 albedo = mix(shadow_tint, snow_color, 0.42 + 0.58 * sky_term);
	albedo *= 0.9 + micro * 0.22;
	albedo = mix(albedo, shadow_tint, subsurface * (1.0 - sky_term) * 0.35);

	float glitter_id = hash12(floor(uv * 48.0 + dunes * 4.0));
	float spark_mask = step(sparkle_density, glitter_id) * sparkle_amount;
	float view_spark = pow(clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 6.0);

	ALBEDO = albedo;
	ROUGHNESS = clamp(roughness_base + grain * 0.18 - spark_mask * 0.45 - abs(cord) * 0.08, 0.18, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.42 + spark_mask * 0.4;
	EMISSION = sparkle_color * spark_mask * view_spark * 1.8;
	AO = clamp(0.78 + dunes * 0.22, 0.65, 1.0);
}
