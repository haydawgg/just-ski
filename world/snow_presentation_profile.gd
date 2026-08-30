class_name SnowPresentationProfile
extends Resource

@export_category("Large-scale Form")
@export var form_light_direction_world_xz := Vector2(-0.34, 0.94)
@export_range(0.0, 0.3, 0.005) var packed_form_contrast := 0.18
@export_range(0.0, 0.3, 0.005) var groomed_form_contrast := 0.17
@export_range(0.0, 0.3, 0.005) var powder_form_contrast := 0.145
@export_range(0.0, 0.3, 0.005) var steepness_contrast := 0.15
@export_range(0.005, 0.2, 0.001) var medium_variation_scale := 0.028
@export_range(0.0, 0.25, 0.005) var packed_medium_variation := 0.15
@export_range(0.0, 0.25, 0.005) var groomed_medium_variation := 0.14
@export_range(0.0, 0.25, 0.005) var powder_medium_variation := 0.16
@export_range(0.001, 0.05, 0.001) var broad_variation_scale := 0.018
@export_range(0.0, 0.25, 0.005) var packed_broad_variation := 0.2
@export_range(0.0, 0.25, 0.005) var groomed_broad_variation := 0.18
@export_range(0.0, 0.25, 0.005) var powder_broad_variation := 0.2

@export_category("Snow Color")
@export var warm_tint := Color(1.0, 0.985, 0.955)
@export var cool_tint := Color(0.965, 0.982, 0.998)
@export var packed_color := Color(0.94, 0.95, 0.955)
@export var packed_shadow_tint := Color(0.71, 0.735, 0.75)
@export var groomed_color := Color(0.955, 0.96, 0.96)
@export var groomed_shadow_tint := Color(0.74, 0.755, 0.765)
@export var powder_color := Color(0.965, 0.975, 0.98)
@export var powder_shadow_tint := Color(0.73, 0.755, 0.775)
@export_range(0.0, 1.0, 0.01) var temperature_amount := 0.72
@export_range(0.2, 0.8, 0.01) var minimum_albedo_luminance := 0.44

@export_category("Surface Response")
@export_range(0.2, 1.0, 0.01) var packed_roughness := 0.72
@export_range(0.2, 1.0, 0.01) var groomed_roughness := 0.76
@export_range(0.2, 1.0, 0.01) var powder_roughness := 0.84
@export_range(0.0, 0.3, 0.005) var roughness_variation := 0.14
@export_range(0.0, 100.0, 0.5) var detail_near_distance := 16.0
@export_range(1.0, 200.0, 0.5) var detail_far_distance := 50.0
