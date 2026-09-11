class_name SkierOutfitProfile
extends Resource

@export_group("Clothing")
@export var jacket_color := Color("#c9503c")
@export var jacket_panel_color := Color("#7e3540")
@export var jacket_trim_color := Color("#d9a441")
@export var jacket_detail_color := Color("#263b46")
@export var pants_color := Color("#1a3448")
@export var skin_color := Color("#a96f52")
@export var glove_color := Color("#101c28")
@export var boot_color := Color("#131f2b")

@export_group("Headwear")
@export var helmet_color := Color("#162832")
@export var goggle_frame_color := Color("#0d151d")
@export var goggle_lens_color := Color("#3aa8b5")

@export_group("Equipment")
@export var ski_base_color := Color("#1d5a74")
@export var ski_accent_color := Color("#d9a441")
@export var pole_color := Color("#9fb9c4")

@export_group("Surface Response")
@export_range(0.0, 1.0) var cloth_roughness := 0.82
@export_range(0.0, 1.0) var cloth_specular := 0.26
@export_range(0.0, 1.0) var pants_roughness := 0.82
@export_range(0.0, 1.0) var pants_specular := 0.28
@export_range(0.0, 1.0) var skin_roughness := 0.56
@export_range(0.0, 1.0) var skin_specular := 0.34
@export_range(0.0, 1.0) var hardgoods_roughness := 0.42
@export_range(0.0, 1.0) var hardgoods_specular := 0.56
@export_range(0.0, 1.0) var lens_roughness := 0.26
@export_range(0.0, 1.0) var lens_specular := 0.82
@export_range(0.0, 1.0) var ski_roughness := 0.38
@export_range(0.0, 1.0) var hardgoods_metallic := 0.12
@export_range(0.0, 1.0) var lens_metallic := 0.32
