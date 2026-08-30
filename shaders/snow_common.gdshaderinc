uniform sampler2D snow_albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_detail_texture : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 snow_color : source_color = vec3(0.94, 0.97, 1.0);
uniform vec3 shadow_tint : source_color = vec3(0.56, 0.71, 0.86);
uniform float roughness_base : hint_range(0.2, 1.0) = 0.78;
uniform float texture_world_size : hint_range(0.25, 8.0) = 2.0;
uniform float triplanar_sharpness : hint_range(1.0, 12.0) = 4.0;
uniform float albedo_texture_strength : hint_range(0.0, 1.0) = 0.42;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.7;
uniform float roughness_texture_strength : hint_range(0.0, 1.0) = 0.72;
uniform float macro_tint_amount : hint_range(0.0, 0.25) = 0.055;
uniform float macro_scale : hint_range(0.005, 0.2) = 0.035;
uniform float far_macro_tint_amount : hint_range(0.0, 0.25) = 0.08;
uniform float far_macro_scale : hint_range(0.001, 0.05) = 0.012;
uniform vec3 warm_snow_tint : source_color = vec3(1.0, 0.985, 0.955);
uniform vec3 cool_snow_tint : source_color = vec3(0.965, 0.985, 1.0);
uniform float macro_temperature_amount : hint_range(0.0, 1.0) = 0.8;
uniform float macro_roughness_amount : hint_range(0.0, 0.3) = 0.1;
uniform float slope_contrast_strength : hint_range(0.0, 0.25) = 0.07;
uniform vec2 form_light_direction_world_xz = vec2(-0.34, 0.94);
uniform float form_contrast_strength : hint_range(0.0, 0.3) = 0.1;
uniform float steepness_contrast_strength : hint_range(0.0, 0.3) = 0.1;
uniform vec2 wind_direction_world_xz = vec2(0.82, -0.57);
uniform float wind_crust_amount : hint_range(0.0, 0.2) = 0.035;
uniform vec3 feature_tint : source_color = vec3(0.86, 0.9, 0.94);
uniform float feature_emphasis : hint_range(0.0, 1.0) = 0.0;
uniform float disturbed_roughness_offset : hint_range(-0.2, 0.2) = 0.08;
uniform float disturbed_detail_boost : hint_range(0.0, 0.5) = 0.16;
uniform float detail_near_distance : hint_range(0.0, 100.0) = 20.0;
uniform float detail_far_distance : hint_range(1.0, 200.0) = 60.0;
uniform vec2 groom_direction_world_xz = vec2(0.0, -1.0);
uniform float corduroy_amount : hint_range(0.0, 1.0) = 0.0;
uniform float corduroy_frequency : hint_range(0.25, 8.0) = 3.0;

varying vec3 snow_world_position;
varying vec3 snow_world_normal;

struct SnowTriplanarSample {
	vec3 albedo;
	vec3 normal_world;
	float roughness;
	float translucency;
};

float snow_hash12(vec2 position) {
	vec3 p3 = fract(vec3(position.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float snow_value_noise(vec2 position) {
	vec2 cell = floor(position);
	vec2 blend = fract(position);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float a = snow_hash12(cell);
	float b = snow_hash12(cell + vec2(1.0, 0.0));
	float c = snow_hash12(cell + vec2(0.0, 1.0));
	float d = snow_hash12(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

vec3 snow_decode_normal(vec2 encoded_normal) {
	vec2 xy = encoded_normal * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.0001));
	return normalize(vec3(xy, z));
}

vec3 snow_axis_normal_x(vec3 tangent_normal, float axis_sign) {
	return vec3(axis_sign * tangent_normal.z, -axis_sign * tangent_normal.y, tangent_normal.x);
}

vec3 snow_axis_normal_y(vec3 tangent_normal, float axis_sign) {
	return vec3(tangent_normal.x, axis_sign * tangent_normal.z, -axis_sign * tangent_normal.y);
}

vec3 snow_axis_normal_z(vec3 tangent_normal, float axis_sign) {
	return vec3(tangent_normal.x, axis_sign * tangent_normal.y, axis_sign * tangent_normal.z);
}

SnowTriplanarSample sample_triplanar(vec3 world_position, vec3 geometry_normal) {
	vec3 weights = pow(abs(geometry_normal), vec3(triplanar_sharpness));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 coordinate = world_position / max(texture_world_size, 0.001);

	vec3 albedo_x = texture(snow_albedo_texture, coordinate.zy).rgb;
	vec3 albedo_y = texture(snow_albedo_texture, coordinate.xz).rgb;
	vec3 albedo_z = texture(snow_albedo_texture, coordinate.xy).rgb;
	vec4 detail_x = texture(snow_detail_texture, coordinate.zy);
	vec4 detail_y = texture(snow_detail_texture, coordinate.xz);
	vec4 detail_z = texture(snow_detail_texture, coordinate.xy);

	float sign_x = geometry_normal.x < 0.0 ? -1.0 : 1.0;
	float sign_y = geometry_normal.y < 0.0 ? -1.0 : 1.0;
	float sign_z = geometry_normal.z < 0.0 ? -1.0 : 1.0;
	vec3 mapped_x = snow_axis_normal_x(snow_decode_normal(detail_x.rg), sign_x);
	vec3 mapped_y = snow_axis_normal_y(snow_decode_normal(detail_y.rg), sign_y);
	vec3 mapped_z = snow_axis_normal_z(snow_decode_normal(detail_z.rg), sign_z);
	vec3 normal_x = normalize(geometry_normal + mapped_x - vec3(sign_x, 0.0, 0.0));
	vec3 normal_y = normalize(geometry_normal + mapped_y - vec3(0.0, sign_y, 0.0));
	vec3 normal_z = normalize(geometry_normal + mapped_z - vec3(0.0, 0.0, sign_z));

	SnowTriplanarSample result;
	result.albedo = albedo_x * weights.x + albedo_y * weights.y + albedo_z * weights.z;
	result.normal_world = normalize(normal_x * weights.x + normal_y * weights.y + normal_z * weights.z);
	result.roughness = dot(vec3(detail_x.b, detail_y.b, detail_z.b), weights);
	result.translucency = dot(vec3(detail_x.a, detail_y.a, detail_z.a), weights);
	return result;
}

float snow_detail_visibility(vec3 camera_world_position) {
	float distance_to_camera = distance(camera_world_position, snow_world_position);
	return 1.0 - smoothstep(detail_near_distance, max(detail_far_distance, detail_near_distance + 0.01), distance_to_camera);
}

vec3 snow_apply_corduroy(vec3 geometry_normal, float detail_visibility, float disturbance) {
	vec2 track_direction = groom_direction_world_xz;
	if (dot(track_direction, track_direction) < 0.0001) {
		track_direction = vec2(0.0, -1.0);
	}
	track_direction = normalize(track_direction);
	vec2 across_direction = vec2(-track_direction.y, track_direction.x);
	vec3 across_world = vec3(across_direction.x, 0.0, across_direction.y);
	across_world -= geometry_normal * dot(across_world, geometry_normal);
	if (dot(across_world, across_world) < 0.0001) {
		return geometry_normal;
	}
	across_world = normalize(across_world);
	float phase = dot(snow_world_position.xz, across_direction) * corduroy_frequency * TAU;
	float grooming_visibility = 1.0 - clamp(disturbance * 0.82, 0.0, 0.82);
	float gradient = cos(phase) * corduroy_amount * grooming_visibility * detail_visibility * 0.2;
	return normalize(geometry_normal - across_world * gradient);
}

void snow_surface(
	vec3 camera_world_position,
	mat3 view_rotation,
	out vec3 surface_albedo,
	out vec3 surface_normal_view,
	out float surface_roughness,
	out float surface_translucency,
	out float detail_visibility
) {
	vec3 geometry_normal = normalize(snow_world_normal);
	detail_visibility = snow_detail_visibility(camera_world_position);
	float sky_term = clamp(geometry_normal.y * 0.5 + 0.5, 0.0, 1.0);
	float near_macro = snow_value_noise(snow_world_position.xz * macro_scale);
	float far_macro = snow_value_noise(snow_world_position.xz * far_macro_scale + vec2(17.0, -9.0));
	float temperature = snow_value_noise(snow_world_position.xz * far_macro_scale * 0.63 + vec2(-31.0, 24.0));
	vec2 safe_wind_direction = dot(wind_direction_world_xz, wind_direction_world_xz) > 0.0001 ? normalize(wind_direction_world_xz) : vec2(0.82, -0.57);
	float wind_crust = snow_value_noise(vec2(dot(snow_world_position.xz, safe_wind_direction) * 0.055, dot(snow_world_position.xz, vec2(-safe_wind_direction.y, safe_wind_direction.x)) * 0.012));
	float disturbance_noise = smoothstep(0.24, 0.78, mix(near_macro, wind_crust, 0.62));
	float disturbance = feature_emphasis * mix(0.38, 1.0, disturbance_noise);
	float slope_aspect = dot(geometry_normal.xz, safe_wind_direction);
	vec2 safe_form_direction = dot(form_light_direction_world_xz, form_light_direction_world_xz) > 0.0001 ? normalize(form_light_direction_world_xz) : vec2(0.0, 1.0);
	float form_aspect = dot(geometry_normal.xz, safe_form_direction);
	float steepness = 1.0 - clamp(geometry_normal.y, 0.0, 1.0);
	surface_albedo = mix(shadow_tint, snow_color, 0.42 + 0.58 * sky_term);
	vec3 temperature_tint = mix(cool_snow_tint, warm_snow_tint, temperature);
	surface_albedo *= mix(vec3(1.0), temperature_tint, macro_temperature_amount);
	surface_albedo *= 1.0 + (far_macro - 0.5) * far_macro_tint_amount;
	surface_albedo *= 1.0 + (near_macro - 0.5) * macro_tint_amount * detail_visibility;
	surface_albedo *= 1.0 + slope_aspect * slope_contrast_strength;
	surface_albedo *= 1.0 + form_aspect * form_contrast_strength - steepness * steepness_contrast_strength;
	surface_albedo *= 1.0 + (wind_crust - 0.5) * wind_crust_amount;
	surface_albedo = mix(surface_albedo, feature_tint, disturbance * 0.12);
	surface_roughness = roughness_base + (far_macro - 0.5) * macro_roughness_amount + disturbance * disturbed_roughness_offset;
	surface_translucency = 0.5;

	vec3 detailed_normal = geometry_normal;
	if (detail_visibility > 0.001) {
		SnowTriplanarSample detail = sample_triplanar(snow_world_position, geometry_normal);
		float visible_albedo_detail = clamp(albedo_texture_strength + disturbance * disturbed_detail_boost, 0.0, 1.0) * detail_visibility;
		vec3 texture_tint = mix(vec3(1.0), detail.albedo, visible_albedo_detail);
		surface_albedo *= texture_tint;
		float visible_normal_detail = normal_strength * (1.0 + disturbance * 0.3) * detail_visibility;
		detailed_normal = normalize(mix(geometry_normal, detail.normal_world, visible_normal_detail));
		surface_roughness += (detail.roughness - 0.5) * roughness_texture_strength * detail_visibility * 0.32;
		surface_translucency = mix(0.5, detail.translucency, detail_visibility);
	}

	detailed_normal = snow_apply_corduroy(detailed_normal, detail_visibility, disturbance);
	surface_roughness = clamp(surface_roughness, 0.28, 0.98);
	surface_normal_view = normalize(view_rotation * detailed_normal);
}

float snow_crystal_mask(float detail_visibility, float sparkle_amount, float sparkle_density) {
	float crystal = snow_hash12(floor(snow_world_position.xz * 42.0));
	return step(sparkle_density, crystal) * sparkle_amount * detail_visibility;
}
