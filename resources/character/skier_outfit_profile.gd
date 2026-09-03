class_name SkierOutfitProfile
extends Resource

@export_group("Clothing")
@export var jacket_color := Color("#e2644f")
@export var pants_color := Color("#132b3d")
@export var skin_color := Color("#b9795b")
@export var glove_color := Color("#081521")
@export var boot_color := Color("#0d1c2a")

@export_group("Headwear")
@export var helmet_color := Color("#102331")
@export var goggle_frame_color := Color("#061019")
@export var goggle_lens_color := Color("#4fd9d3")

@export_group("Equipment")
@export var ski_base_color := Color("#176783")
@export var ski_accent_color := Color("#f0b43b")
@export var pole_color := Color("#b7d5df")

@export_group("Surface Response")
@export_range(0.0, 1.0) var cloth_roughness := 0.78
@export_range(0.0, 1.0) var cloth_specular := 0.30
@export_range(0.0, 1.0) var pants_roughness := 0.68
@export_range(0.0, 1.0) var pants_specular := 0.40
@export_range(0.0, 1.0) var skin_roughness := 0.56
@export_range(0.0, 1.0) var skin_specular := 0.34
@export_range(0.0, 1.0) var hardgoods_roughness := 0.42
@export_range(0.0, 1.0) var hardgoods_specular := 0.56
@export_range(0.0, 1.0) var lens_roughness := 0.26
@export_range(0.0, 1.0) var lens_specular := 0.82
@export_range(0.0, 1.0) var ski_roughness := 0.38
@export_range(0.0, 1.0) var hardgoods_metallic := 0.12
@export_range(0.0, 1.0) var lens_metallic := 0.32
