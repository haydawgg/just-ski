class_name ResortEnvironmentProfile
extends Resource

@export_category("Sky")
@export var sky_top_color := Color(0.20, 0.39, 0.64)
@export var sky_horizon_color := Color(0.78, 0.86, 0.92)
@export_range(0.5, 2.0, 0.01) var sky_energy := 1.02
@export_range(0.01, 1.0, 0.01) var sky_curve := 0.32
@export var ground_bottom_color := Color(0.68, 0.75, 0.82)
@export var ground_horizon_color := Color(0.88, 0.91, 0.94)
@export_range(0.5, 2.0, 0.01) var ground_energy := 0.88
@export_range(0.01, 1.0, 0.01) var ground_curve := 0.28

@export_category("Sun and Shadows")
@export var sun_rotation_degrees := Vector3(-36.0, -48.0, 0.0)
@export var sun_color := Color(1.0, 0.95, 0.86)
@export_range(0.0, 4.0, 0.01) var sun_energy := 1.38
@export_range(0.0, 2.0, 0.01) var sun_indirect_energy := 0.82
@export_range(0.0, 1.0, 0.01) var sun_specular := 0.72
@export_range(0.0, 1.0, 0.01) var shadow_opacity := 0.58
@export_range(0.1, 4.0, 0.05) var shadow_blur := 1.25
@export_range(0.0, 5.0, 0.05) var sun_angular_distance := 0.8
@export_range(0.5, 1.0, 0.01) var shadow_fade_start := 0.72

@export_category("Ambient and Tonemapping")
@export_range(0.0, 1.0, 0.01) var ambient_sky_contribution := 0.9
@export_range(0.0, 4.0, 0.01) var ambient_energy := 0.96
@export_range(0.1, 4.0, 0.01) var exposure := 0.98
@export_range(0.1, 16.0, 0.1) var white_point := 6.4
@export_range(0.5, 1.5, 0.01) var brightness := 1.0
@export_range(0.5, 1.5, 0.01) var contrast := 1.11
@export_range(0.0, 2.0, 0.01) var saturation := 0.92
@export_range(0.0, 2.0, 0.01) var glow_intensity := 0.14
@export_range(0.0, 2.0, 0.01) var glow_strength := 0.5
@export_range(0.0, 1.0, 0.005) var glow_bloom := 0.01
@export_range(0.0, 4.0, 0.01) var glow_hdr_threshold := 1.05

@export_category("Local Depth")
@export_range(0.05, 5.0, 0.05) var ssao_radius := 0.78
@export_range(0.0, 8.0, 0.05) var ssao_intensity := 1.3
@export_range(0.1, 8.0, 0.05) var ssao_power := 1.35
@export_range(0.0, 1.0, 0.01) var ssao_detail := 0.68
@export_range(0.0, 1.0, 0.01) var ssao_horizon := 0.08
@export_range(0.0, 1.0, 0.01) var ssao_light_affect := 0.08

@export_category("Atmospheric Depth")
@export var fog_color := Color(0.82, 0.87, 0.91)
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter := 0.12
@export_range(0.0, 0.02, 0.0001) var fog_density := 0.0019
@export_range(0.0, 1.0, 0.01) var fog_aerial_perspective := 0.82
@export_range(0.0, 1.0, 0.01) var fog_sky_affect := 0.3
@export_range(-100.0, 100.0, 0.5) var fog_height := -6.0
@export_range(0.0, 1.0, 0.001) var fog_height_density := 0.026
