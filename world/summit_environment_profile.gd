class_name SummitEnvironmentProfile
extends Resource

## Presentation-only profile for the summit-to-first-landing environment slice.
##
## The existing MainSnowFace collision body remains authoritative. This profile
## controls the deterministic render surface, backdrop, and decorative assets
## that can be turned off when comparing against the graybox baseline.

@export var enabled := true
@export var backdrop_enabled := true
@export var dressing_enabled := true
@export_range(0.5, 8.0, 0.5) var sample_spacing_m := 3.0
@export_range(8.0, 31.0, 0.5) var playable_half_width_m := 24.0
@export_range(24.0, 32.0, 0.5) var outer_half_width_m := 31.5
@export_range(0.0, 3.0, 0.05) var shoulder_amplitude_m := 0.65
@export_range(0.0, 0.2, 0.001) var relief_frequency := 0.032
@export_range(0.0, 0.2, 0.001) var secondary_relief_frequency := 0.071
@export var relief_seed := 5173
@export_range(0.0, 0.1, 0.001) var surface_offset_m := 0.008
@export_range(100.0, 1200.0, 10.0) var terrain_lod_end_m := 900.0
@export_range(300.0, 2000.0, 10.0) var backdrop_lod_end_m := 1400.0
@export var lift_line_enabled := true
@export var rock_clusters_enabled := true
