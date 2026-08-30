shader_type spatial;

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 snow_tint : source_color = vec4(0.86, 0.93, 0.98, 0.74);

varying float particle_camera_distance;

void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	particle_camera_distance = distance(CAMERA_POSITION_WORLD, world_vertex);
	float near_size = smoothstep(0.45, 1.8, particle_camera_distance);
	VERTEX *= mix(0.3, 1.0, near_size);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float soft_disc = 1.0 - smoothstep(0.42, 1.0, radius);
	float irregular = 0.88 + 0.12 * sin(centered_uv.x * 11.0 + centered_uv.y * 7.0);
	float distance_fade = smoothstep(0.42, 1.35, particle_camera_distance);
	ALBEDO = snow_tint.rgb;
	ALPHA = snow_tint.a * COLOR.a * soft_disc * irregular * distance_fade;
}
