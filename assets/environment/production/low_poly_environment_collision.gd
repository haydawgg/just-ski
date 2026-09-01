class_name LowPolyEnvironmentCollision
extends StaticBody3D

## Collision companion for LowPolyEnvironmentAsset scenes. Shapes use the
## same nominal dimensions as their visible counterparts and are authored in
## meters from the shared snow-contact origin.

enum AssetKind { PARK_TREE, COURSE_BOUNDARY, LIFT_TOWER, SNOWMAKER, TRAIL_BOARD }

@export var asset_kind: AssetKind = AssetKind.PARK_TREE

var _built := false

func _ready() -> void:
	build_now()

func build_now() -> void:
	if _built:
		return
	_built = true
	match asset_kind:
		AssetKind.PARK_TREE:
			_add_cylinder("TreeEnvelope", 1.35, 5.6, Vector3(0.0, 2.8, 0.0))
		AssetKind.COURSE_BOUNDARY:
			for along: float in [-9.9, -5.0, 0.0, 5.0, 9.9]:
				_add_box("BoundaryPost", Vector3(0.2, 1.1, 0.2), Vector3(0.0, 0.55, along))
			for height: float in [0.36, 0.82]:
				_add_box("BoundaryRail", Vector3(0.12, 0.12, 20.0), Vector3(0.0, height, 0.0))
		AssetKind.LIFT_TOWER:
			for side: float in [-1.0, 1.0]:
				_add_cylinder("TowerLeg", 0.13, 6.3, Vector3(side * 0.82, 3.15, 0.0))
			_add_box("TowerCrossbar", Vector3(3.2, 0.22, 0.5), Vector3(0.0, 6.05, 0.0))
		AssetKind.SNOWMAKER:
			_add_box("SnowmakerBase", Vector3(0.72, 0.2, 0.82), Vector3(0.0, 0.1, 0.0))
			_add_box("SnowmakerBody", Vector3(0.72, 1.8, 1.1), Vector3(0.0, 1.1, -0.08))
		AssetKind.TRAIL_BOARD:
			for side: float in [-1.0, 1.0]:
				_add_box("BoardPost", Vector3(0.12, 1.55, 0.14), Vector3(side * 0.56, 0.775, 0.0))
			_add_box("TrailBoardFace", Vector3(1.6, 0.65, 0.2), Vector3(0.0, 1.65, 0.0))

func _add_box(node_name: String, size: Vector3, position: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = position
	add_child(shape_node)

func _add_cylinder(node_name: String, radius: float, height: float, position: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shape_node.shape = shape
	shape_node.position = position
	add_child(shape_node)
