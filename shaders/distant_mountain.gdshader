shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.42, 0.55, 0.66);
uniform vec3 haze_color : source_color = vec3(0.72, 0.8, 0.86);
uniform float haze_start_distance : hint_range(0.0, 1000.0) = 170.0;
uniform float haze_end_distance : hint_range(1.0, 1200.0) = 620.0;
uniform float haze_blend : hint_range(0.0, 1.0) = 0.28;
uniform float facet_value_range : hint_range(0.0, 0.35) = 0.08;
uniform float mountain_height = 100.0;

varying vec3 mountain_world_position;
varying vec3 mountain_local_position;

void vertex() {
	mountain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mountain_local_position = VERTEX;
}

void fragment() {
	float mountain_camera_distance = distance(CAMERA_POSITION_WORLD, mountain_world_position);
	float depth_haze = smoothstep(haze_start_distance, max(haze_end_distance, haze_start_distance + 0.01), mountain_camera_distance);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facet_value = 1.0 + clamp(world_normal.y, -1.0, 1.0) * facet_value_range;
	float strata = sin(mountain_local_position.y * 0.28 + mountain_local_position.x * 0.085 + sin(mountain_local_position.z * 0.16) * 2.0);
	float altitude = mountain_local_position.y / max(mountain_height, 1.0);
	float snow_line = smoothstep(0.1, 0.55, altitude + world_normal.y * 0.28 + strata * 0.045);
	float snow = snow_line * smoothstep(0.22, 0.7, world_normal.y);
	vec3 rock = base_color * (0.72 + strata * 0.07);
	vec3 surface = mix(rock, vec3(0.88, 0.93, 0.97), snow);
	// Global environment fog is the primary aerial-perspective system on this
	// project, so the shader only adds a bounded local blend on top of it to
	// keep near/mid/far value layers without double-washing distant peaks.
	ALBEDO = mix(surface, haze_color, depth_haze * haze_blend) * facet_value;
	ROUGHNESS = 0.98;
}
