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
	# Material block mirrors SkeletonSkierRig._build_attachments so the same
	# outfit profile renders identically on both adapters (specular/roughness
	# values included, not just albedo).
	var dark := SkierEquipment.material(outfit_profile.boot_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var jacket := SkierEquipment.material(outfit_profile.jacket_color, outfit_profile.cloth_roughness, 0.0, outfit_profile.cloth_specular)
	var jacket_trim := SkierEquipment.material(outfit_profile.jacket_trim_color, outfit_profile.cloth_roughness, 0.02, outfit_profile.cloth_specular)
	var jacket_accent := SkierEquipment.material(outfit_profile.jacket_panel_color, outfit_profile.cloth_roughness, 0.0, outfit_profile.cloth_specular)
	var jacket_detail := SkierEquipment.material(outfit_profile.jacket_detail_color, outfit_profile.cloth_roughness, 0.0, outfit_profile.cloth_specular)
	var pants := SkierEquipment.material(outfit_profile.pants_color, outfit_profile.pants_roughness, 0.0, outfit_profile.pants_specular)
	var skin := SkierEquipment.material(outfit_profile.skin_color, outfit_profile.skin_roughness, 0.0, outfit_profile.skin_specular)
	var glove_mat := SkierEquipment.material(outfit_profile.glove_color, outfit_profile.hardgoods_roughness, 0.0, outfit_profile.hardgoods_specular)
	var accent := SkierEquipment.material(outfit_profile.ski_accent_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var boot_accent := SkierEquipment.material(outfit_profile.ski_accent_color.darkened(0.32), 0.48, 0.18, outfit_profile.hardgoods_specular)
	var ski_base := SkierEquipment.material(outfit_profile.ski_base_color, outfit_profile.ski_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var lens := SkierEquipment.material(outfit_profile.goggle_lens_color, outfit_profile.lens_roughness, outfit_profile.lens_metallic, outfit_profile.lens_specular)
	var frame := SkierEquipment.material(outfit_profile.goggle_frame_color, 0.36, 0.18, outfit_profile.hardgoods_specular)
	var helmet := SkierEquipment.material(outfit_profile.helmet_color, outfit_profile.hardgoods_roughness, outfit_profile.hardgoods_metallic, outfit_profile.hardgoods_specular)
	var pole := SkierEquipment.material(outfit_profile.pole_color.darkened(0.16), outfit_profile.hardgoods_roughness, 0.28, outfit_profile.hardgoods_specular)
	# Pelvis shell covers the ±0.27m hip joints; the torso is an oval that
	# fits inside its own pelvis width and the shoulder block depth instead
	# of a barrel protruding ~14cm front and back.
	SkierEquipment.add_box(driver.joint(&"pelvis"), "PelvisMesh", Vector3(0.56, 0.22, 0.32), Vector3(0.0, 0.05, 0.0), pants)
	SkierEquipment.add_sphere(driver.joint(&"spine"), "TorsoMesh", 0.26, Vector3(0.0, 0.34, 0.0), jacket, Vector3(1.0, 1.38, 0.75))
	SkierEquipment.add_box(driver.joint(&"chest"), "ShoulderJacket", Vector3(0.84, 0.20, 0.40), Vector3(0.0, 0.14, 0.0), jacket)
	# Short skin column so the head does not float above the jacket on a bare
	# joint pivot. Production covers this with the base-mesh neck.
	SkierEquipment.add_capsule(driver.joint(&"head"), "NeckMesh", 0.07, 0.22, Vector3(0.0, -0.04, 0.0), skin)
	SkierEquipment.build_jacket_details(driver.joint(&"spine"), driver.joint(&"chest"), jacket_accent, jacket_detail, jacket_trim,
		0.196, -0.197, Vector3(-0.09, 0.05, -0.174))
	# Head radius 0.112 fits inside the shared helmet shell (inner 0.152). The
	# previous 0.20 sphere swallowed the helmet whole.
	SkierEquipment.add_sphere(driver.joint(&"head"), "HeadMesh", 0.112, Vector3(0.0, 0.10, 0.0), skin)
	# Jaw mass gives the chin/lower lip somewhere to live: without it the mouth
	# would float ahead of the neck column. Front reaches mount z≈-0.099 where
	# the mouth seats.
	SkierEquipment.add_sphere(driver.joint(&"head"), "JawMesh", 0.095, Vector3(0.0, 0.0, -0.03), skin, Vector3(0.79, 0.95, 1.0))
	SkierEquipment.build_headwear(driver.joint(&"head"), helmet, frame, lens)
	SkierEquipment.build_face(driver.joint(&"head"), SkierEquipment.material(outfit_profile.skin_color.darkened(0.45), outfit_profile.skin_roughness, 0.0, outfit_profile.skin_specular), Vector3(0.0, 0.03, -0.123))
	for side: StringName in [&"left", &"right"]:
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_hip")), side.capitalize() + "Thigh", 0.095, 0.56, Vector3(0.0, -0.26, 0.0), pants)
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_knee")), side.capitalize() + "Shin", 0.08, 0.52, Vector3(0.0, -0.24, 0.0), pants)
		SkierEquipment.build_boot(driver.joint(StringName(side + "_boot")), side, dark, boot_accent)
		SkierEquipment.build_ski(driver.joint(StringName(side + "_ski")), side, ski_base, accent)
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_shoulder")), side.capitalize() + "UpperArm", 0.085, 0.46, Vector3(0.0, -0.21, 0.0), jacket)
		SkierEquipment.add_capsule(driver.joint(StringName(side + "_elbow")), side.capitalize() + "Forearm", 0.07, 0.4, Vector3(0.0, -0.18, 0.0), jacket)
		# Elongated hand with the outfit glove color (not boot dark): reads as
		# a mitt at gameplay distance instead of an 18cm ball.
		SkierEquipment.add_sphere(driver.joint(StringName(side + "_hand")), side.capitalize() + "Glove", 0.055, Vector3.ZERO, glove_mat, Vector3(0.95, 1.3, 1.1))
		SkierEquipment.build_sleeves(
			driver.joint(StringName(side + "_shoulder")),
			driver.joint(StringName(side + "_elbow")),
			side, jacket, dark)
		SkierEquipment.build_pole(driver.joint(StringName(side + "_pole")), side, pole, dark)
