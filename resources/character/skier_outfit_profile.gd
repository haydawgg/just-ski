class_name SkierOutfitProfile
extends Resource

@export_group("Clothing")
@export var jacket_color := Color("#8f3546")
@export var pants_color := Color("#1d2a35")
@export var skin_color := Color("#c88f6a")
@export var glove_color := Color("#101920")
@export var boot_color := Color("#131c23")

@export_group("Headwear")
@export var helmet_color := Color("#17242c")
@export var goggle_frame_color := Color("#090f14")
@export var goggle_lens_color := Color("#c46d32")

@export_group("Equipment")
@export var ski_base_color := Color("#314e5b")
@export var ski_accent_color := Color("#d79a35")
@export var pole_color := Color("#263d49")

@export_group("Surface Response")
@export_range(0.0, 1.0) var cloth_roughness := 0.82
@export_range(0.0, 1.0) var hardgoods_roughness := 0.42
@export_range(0.0, 1.0) var lens_roughness := 0.18
@export_range(0.0, 1.0) var ski_roughness := 0.38
@export_range(0.0, 1.0) var hardgoods_metallic := 0.12
@export_range(0.0, 1.0) var lens_metallic := 0.48
