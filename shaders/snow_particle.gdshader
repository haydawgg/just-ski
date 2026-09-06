shader_type spatial;

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

uniform vec4 snow_tint : source_color = vec4(0.86, 0.93, 0.98, 0.74);
uniform float height_limit : hint_range(0.5, 5.0) = 2.2;
uniform float height_fade_range : hint_range(0.1, 1.5) = 0.65;
uniform float emitter_base_height = 0.0;
uniform float shape_aspect : hint_range(0.75, 3.5) = 1.65;

varying float particle_camera_distance;
varying float height_keep;

void vertex() {
	vec3 world_center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 particle_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	particle_size.x *= max(shape_aspect * 0.72, 0.75);
	vec3 world_vertex = world_center + INV_VIEW_MATRIX[0].xyz * VERTEX.x * particle_size.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y * particle_size.y;
	particle_camera_distance = distance(CAMERA_POSITION_WORLD, world_vertex);
	float height_above_emitter = max(world_vertex.y - emitter_base_height, 0.0);
	height_keep = 1.0 - smoothstep(height_limit, height_limit + max(height_fade_range, 0.01), height_above_emitter);
	float near_size = smoothstep(0.45, 1.8, particle_camera_distance);
	world_vertex = world_center + INV_VIEW_MATRIX[0].xyz * VERTEX.x * particle_size.x * mix(0.3, 1.0, near_size) + INV_VIEW_MATRIX[1].xyz * VERTEX.y * particle_size.y * mix(0.3, 1.0, near_size);
	VERTEX = (VIEW_MATRIX * vec4(world_vertex, 1.0)).xyz;
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	// A spray mote is a short directional fleck, not a round bead. Keep the
	// unit quad footprint stable in the particle system and shape it here so
	// each emitter can choose a readable amount of horizontal stretch.
	float transverse = abs(centered_uv.y);
	float taper = mix(0.92, 0.5, smoothstep(0.15, 1.0, transverse));
	vec2 shape_coord = vec2(centered_uv.x / max(1.15 * taper, 0.75), centered_uv.y * 1.8);
	float radius = length(shape_coord);
	float angle = atan(shape_coord.y, shape_coord.x);
	float edge_shape = 0.86 + 0.08 * sin(angle * 3.0 + 0.7) + 0.05 * sin(angle * 7.0 - 1.4);
	float irregular_radius = radius / max(edge_shape, 0.64);
	float soft_edge = 1.0 - smoothstep(0.5, 0.98, irregular_radius);
	float lobe = 0.86 + 0.14 * sin(centered_uv.x * 9.0 + centered_uv.y * 6.0 + angle * 2.0);
	float distance_fade = smoothstep(0.42, 1.35, particle_camera_distance);
	ALBEDO = snow_tint.rgb;
	ALPHA = snow_tint.a * distance_fade * height_keep * soft_edge * lobe;
}
