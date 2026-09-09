class_name SummitLiftLineAsset
extends Node3D

## Decorative lift span for the summit slice. It is intentionally visual-only:
## the existing course boundary and recovery volumes remain the sole off-run
## gameplay constraints.

const SPAN_M := 56.0
var _built := false

func _ready() -> void:
	build_now()

func build_now() -> void:
	if _built:
		return
	_built = true
	set_meta("readability_category", "resort_lift")
	set_meta("non_colliding", true)
	var render := Node3D.new()
	render.name = "Render"
	add_child(render)
	var lod0 := Node3D.new()
	lod0.name = "LOD0"
	render.add_child(lod0)
	var lod1 := Node3D.new()
	lod1.name = "LOD1"
	render.add_child(lod1)
	var metal := _material(Color("#3d535d"), 0.62, 0.3)
	var cable_material := _material(Color("#202e34"), 0.72, 0.45)
	var chair_material := _material(Color("#b46d42"), 0.7, 0.08)
	var chair_dark := _material(Color("#6b4a3e"), 0.76, 0.1)
	for side: float in [-1.0, 1.0]:
		_add_box(lod0, "SupportLeg", Vector3(0.16, 9.0, 0.16), Vector3(side * 1.28, 4.5, side * SPAN_M * 0.5), metal, 0.0, 160.0)
		_add_box(lod0, "SupportFoot", Vector3(0.68, 0.16, 0.68), Vector3(side * 1.28, 0.08, side * SPAN_M * 0.5), metal, 0.0, 160.0)
	_add_box(lod0, "SupportCrossbar", Vector3(3.2, 0.18, 0.18), Vector3(0.0, 8.8, -SPAN_M * 0.5), metal, 0.0, 160.0)
	_add_box(lod0, "SupportCrossbarFar", Vector3(3.2, 0.18, 0.18), Vector3(0.0, 8.8, SPAN_M * 0.5), metal, 0.0, 160.0)
	_add_cylinder(lod0, "Cable", 0.035, 0.035, SPAN_M, Vector3(0.0, 9.05, 0.0), cable_material, 6, 0.0, 160.0, Vector3(90.0, 0.0, 0.0))
	for index: int in 3:
		var z := lerpf(-16.0, 16.0, float(index) / 2.0)
		_add_box(lod0, "ChairSeat", Vector3(1.0, 0.12, 0.34), Vector3(0.0, 4.95, z), chair_material, 0.0, 160.0)
		_add_box(lod0, "ChairBack", Vector3(1.0, 0.78, 0.12), Vector3(0.0, 5.34, z + 0.1), chair_dark, 0.0, 160.0)
		_add_box(lod0, "ChairHanger", Vector3(0.07, 3.55, 0.07), Vector3(0.0, 7.0, z), cable_material, 0.0, 160.0)
		_add_box(lod0, "ChairSafetyBar", Vector3(1.02, 0.045, 0.045), Vector3(0.0, 5.48, z - 0.33), metal, 0.0, 160.0)
		for side: float in [-1.0, 1.0]:
			_add_box(lod0, "ChairSideFrame", Vector3(0.045, 0.045, 0.48), Vector3(side * 0.49, 5.48, z - 0.1), metal, 0.0, 160.0)
	_add_box(lod1, "TowerLowNear", Vector3(1.8, 9.0, 0.5), Vector3(0.0, 4.5, -SPAN_M * 0.5), metal, 110.0, 340.0)
	_add_box(lod1, "TowerLowFar", Vector3(1.8, 9.0, 0.5), Vector3(0.0, 4.5, SPAN_M * 0.5), metal, 110.0, 340.0)
	_add_cylinder(lod1, "CableLow", 0.05, 0.05, SPAN_M, Vector3(0.0, 9.05, 0.0), cable_material, 5, 110.0, 340.0, Vector3(90.0, 0.0, 0.0))
	# Keep the three seats separated in the distance; a single 36m box looked
	# like a floating wall as the detailed chairs faded out.
	for index: int in 3:
		var z := lerpf(-16.0, 16.0, float(index) / 2.0)
		_add_box(lod1, "ChairLow", Vector3(1.0, 0.8, 0.34), Vector3(0.0, 5.2, z), chair_dark, 110.0, 340.0)
		_add_box(lod1, "HangerLow", Vector3(0.07, 3.55, 0.07), Vector3(0.0, 7.0, z), cable_material, 110.0, 340.0)

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, begin: float, end: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visibility_range_begin = begin
	mesh_instance.visibility_range_begin_margin = 16.0 if begin > 0.0 else 0.0
	mesh_instance.visibility_range_end = end
	mesh_instance.visibility_range_end_margin = 24.0
	mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mesh_instance)

func _add_cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, material: Material, segments: int, begin: float, end: float, rotation: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visibility_range_begin = begin
	mesh_instance.visibility_range_begin_margin = 16.0 if begin > 0.0 else 0.0
	mesh_instance.visibility_range_end = end
	mesh_instance.visibility_range_end_margin = 24.0
	mesh_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mesh_instance)

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

