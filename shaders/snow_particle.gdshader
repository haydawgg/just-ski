shader_type spatial;

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 snow_tint : source_color = vec4(0.86, 0.93, 0.98, 0.74);
uniform float height_limit : hint_range(0.5, 5.0) = 2.2;
uniform float height_fade_range : hint_range(0.1, 1.5) = 0.65;
uniform float emitter_base_height = 0.0;

varying float particle_camera_distance;
varying float height_keep;

void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	particle_camera_distance = distance(CAMERA_POSITION_WORLD, world_vertex);
	float height_above = max(world_vertex.y - emitter_base_height, 0.0);
	height_keep = 1.0 - smoothstep(max(height_limit - height_fade_range, 0.0), height_limit, height_above);
	float near_size = smoothstep(0.45, 1.8, particle_camera_distance);
	VERTEX *= mix(0.3, 1.0, near_size);
}

void fragment() {
	float distance_fade = smoothstep(0.42, 1.35, particle_camera_distance);
	ALBEDO = snow_tint.rgb;
	ALPHA = snow_tint.a * COLOR.a * distance_fade * height_keep;
}
