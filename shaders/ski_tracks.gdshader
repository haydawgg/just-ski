shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 compressed_snow_color : source_color = vec3(0.66, 0.74, 0.81);
uniform vec3 disturbed_snow_color : source_color = vec3(0.82, 0.87, 0.91);
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
	ALBEDO = mix(compressed_snow_color, disturbed_snow_color, skid);
	ROUGHNESS = mix(0.52, 0.92, skid) * mix(1.0, 0.78, carve);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ALPHA = COLOR.a * distance_visibility;
}
