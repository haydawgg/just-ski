class_name PrimitiveSkierRig
extends SkierRigAdapter

const DEFAULT_OUTFIT := preload("res://resources/character/default_skier_outfit_profile.tres")

@export var outfit_profile: SkierOutfitProfile = DEFAULT_OUTFIT

func configure(value: SkierPoseDriver, skeleton_profile: Resource = null) -> bool:
	if not super.configure(value, skeleton_profile):
		error_message = "Primitive rig requires a canonical pose driver"
		return false
	_build_meshes()
	return true

func adapter_name() -> String:
	return "primitive"

func _build_meshes() -> void:
	var jacket := SkierEquipment.material(outfit_profile.jacket_color, outfit_profile.cloth_roughness, 0.0)
	var pants := SkierEquipment.material(outfit_profile.pants_color, outfit_profile.pants_roughness, 0.0)
	var skin := SkierEquipment.material(outfit_profile.skin_color, 0.9, 0.0)
	var dark := SkierEquipment.material(outfit_profile.boot_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic)
	var accent := SkierEquipment.material(outfit_profile.ski_accent_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic)
	var boot_accent := SkierEquipment.material(outfit_profile.ski_accent_color.darkened(0.32), 0.48, 0.18)
	var ski_base := SkierEquipment.material(outfit_profile.ski_base_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic)
	var lens := SkierEquipment.material(outfit_profile.goggle_lens_color, outfit_profile.lens_roughness, outfit_profile.lens_metallic)
	var frame := SkierEquipment.material(outfit_profile.goggle_frame_color, 0.36, 0.18)
	var helmet := SkierEquipment.material(outfit_profile.helmet_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic)
	var pole := SkierEquipment.material(outfit_profile.pole_color, outfit_profile.hardgoods_roughness, 0.28)
	SkierEquipment.add_box(driver.joint(&"pelvis"), "PelvisMesh", Vector3(0.52, 0.22, 0.3), Vector3(0.0, 0.05, 0.0), pants)
	SkierEquipment.add_capsule(driver.joint(&"spine"), "TorsoMesh", 0.31, 0.72, Vector3(0.0, 0.34, 0.0), jacket)
	SkierEquipment.add_box(driver.joint(&"chest"), "ShoulderJacket", Vector3(0.74, 0.2, 0.34), Vector3(0.0, 0.14, 0.0), jacket)
	SkierEquipment.add_sphere(driver.joint(&"head"), "HeadMesh", 0.2, Vector3(0.0, 0.11, 0.0), skin)
	SkierEquipment.build_headwear(driver.joint(&"head"), helmet, frame, lens)
	for side: StringName in [&"left", &"right"]:
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_hip")), side.capitalize() + "Thigh", 0.095, 0.56, Vector3(0.0, -0.26, 0.0), pants)
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_knee")), side.capitalize() + "Shin", 0.08, 0.52, Vector3(0.0, -0.24, 0.0), pants)
		SkierEquipment.build_boot(driver.joint(StringName(side + "_boot")), side, dark, boot_accent)
		SkierEquipment.build_ski(driver.joint(StringName(side + "_ski")), side, ski_base, accent)
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_shoulder")), side.capitalize() + "UpperArm", 0.085, 0.46, Vector3(0.0, -0.21, 0.0), jacket)
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_elbow")), side.capitalize() + "Forearm", 0.07, 0.4, Vector3(0.0, -0.18, 0.0), jacket)
		SkierEquipment.add_sphere(driver.joint(StringName(side + "_hand")), side.capitalize() + "Glove", 0.09, Vector3.ZERO, dark)
		SkierEquipment.build_pole(driver.joint(StringName(side + "_pole")), side, pole, dark)
