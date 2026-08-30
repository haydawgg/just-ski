shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.42, 0.55, 0.66);
uniform vec3 haze_color : source_color = vec3(0.72, 0.8, 0.86);
uniform float haze_start_distance : hint_range(0.0, 1000.0) = 170.0;
uniform float haze_end_distance : hint_range(1.0, 1200.0) = 620.0;
uniform float facet_value_range : hint_range(0.0, 0.35) = 0.08;

varying float mountain_camera_distance;

void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mountain_camera_distance = distance(CAMERA_POSITION_WORLD, world_vertex);
}

void fragment() {
	float depth_haze = smoothstep(haze_start_distance, max(haze_end_distance, haze_start_distance + 0.01), mountain_camera_distance);
	float facet_value = 1.0 + clamp(NORMAL.y, -1.0, 1.0) * facet_value_range;
	ALBEDO = mix(base_color, haze_color, depth_haze) * facet_value;
	ROUGHNESS = 0.98;
}
