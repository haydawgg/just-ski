shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 compressed_snow_color : source_color = vec3(0.78, 0.85, 0.9);
uniform vec3 disturbed_snow_color : source_color = vec3(0.94, 0.97, 0.99);
uniform float distance_fade_start : hint_range(10.0, 200.0) = 70.0;
uniform float distance_fade_end : hint_range(20.0, 300.0) = 115.0;

varying vec3 track_world_position;

void vertex() {
	track_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float distance_to_camera = distance(INV_VIEW_MATRIX[3].xyz, track_world_position);
	float distance_visibility = 1.0 - smoothstep(distance_fade_start, distance_fade_end, distance_to_camera);
	float skid = clamp(COLOR.r, 0.0, 1.0);
	float carve = clamp(COLOR.g, 0.0, 1.0);
	float across = UV.x * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.62, 1.0, abs(across));
	float grain = sin(track_world_position.x * 31.0 + sin(track_world_position.z * 13.0)) * sin(track_world_position.z * 29.0);
	float groove = exp(-across * across * 7.0);
	float berm = exp(-pow((abs(across) - 0.66) * 8.0, 2.0));
	ALBEDO = mix(disturbed_snow_color, compressed_snow_color, groove * (1.0 - skid * 0.5));
	ALBEDO *= 1.0 + berm * 0.045 + grain * 0.025;
	ROUGHNESS = mix(0.7, 0.96, skid) * mix(1.0, 0.92, carve);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = COLOR.a * distance_visibility * edge * (0.52 + groove * 0.18 + grain * skid * 0.12);
}
