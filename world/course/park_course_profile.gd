class_name ParkCourseProfile
extends Resource

@export_category("Feature Readability")
@export var snow_feature_marker_color := Color("#2aa6bd")
@export_range(0.08, 0.5, 0.01) var takeoff_marker_depth := 0.44
@export_range(1.0, 6.0, 0.1) var landing_marker_length := 4.5
@export_range(0.04, 0.3, 0.01) var landing_marker_width := 0.22
@export_range(0.005, 0.08, 0.005) var marker_surface_offset := 0.032

func feature_readability() -> Dictionary:
	return {
		"color": snow_feature_marker_color,
		"takeoff_depth": takeoff_marker_depth,
		"landing_length": landing_marker_length,
		"landing_width": landing_marker_width,
		"surface_offset": marker_surface_offset,
	}

func feature_specs() -> Array[Dictionary]:
	return [
		# Summit teaching cluster.
		{"kind": "gate", "name": "SummitStartGate", "x": 0.0, "z": 134.0, "width": 13.0, "color": Color("#55d6be")},
		{"kind": "roller", "name": "SummitRollerA", "x": 0.0, "z": 128.0, "length": 5.0, "height": 0.42, "width": 10.0},
		{"kind": "roller", "name": "SummitRollerB", "x": 0.0, "z": 120.0, "length": 5.5, "height": 0.5, "width": 10.0},
		{"kind": "tabletop", "name": "SmallTable", "route": "air", "difficulty": "beginner", "x": -12.0, "z": 110.0, "speed": 14.0, "lip": 7.0, "width": 8.5, "pop": 0.72},
		{"kind": "rail", "name": "SummitFlatBox", "route": "jib", "difficulty": "beginner", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.2, "friction": 1.15, "approach": 52.0, "drift_bias": -0.18, "points": [Vector3(12.0, 124.0, 0.22), Vector3(12.0, 112.0, 0.22)]},
		{"kind": "rail", "name": "BeginnerTube", "route": "jib", "difficulty": "beginner", "rail_type": GrindRail3D.RailType.PIPE, "radius": 1.0, "friction": 0.7, "approach": 48.0, "drift_bias": 0.14, "points": [Vector3(12.0, 106.0, 0.16), Vector3(12.0, 96.0, 0.16)]},

		# Upper park: three readable lanes.
		{"kind": "side_hit", "name": "UpperLeftSideHit", "x": -22.0, "z": 96.0, "length": 9.0, "height": 1.25, "width": 7.0, "yaw": -18.0},
		{"kind": "roller", "name": "UpperRoller", "x": -12.0, "z": 82.0, "length": 8.0, "height": 0.8, "width": 9.0},
		{"kind": "berm", "name": "UpperBermLeft", "x": -1.0, "z": 98.0, "length": 14.0, "width": 6.0, "bank": 13.0, "yaw": -16.0},
		{"kind": "berm", "name": "UpperBermRight", "x": 2.0, "z": 82.0, "length": 14.0, "width": 6.0, "bank": -13.0, "yaw": 16.0},
		{"kind": "rail", "name": "DownRail", "route": "jib", "difficulty": "beginner", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.55, "approach": 42.0, "drift_bias": -0.22, "points": [Vector3(14.0, 90.0, 0.16), Vector3(14.0, 76.0, 0.16)]},
		{"kind": "bonk", "name": "UpperBonk", "x": 22.0, "z": 76.0, "height": 1.3, "radius": 0.42, "color": Color("#ffc857")},

		# Mid park: jump, mogul, and technical jib choices.
		{"kind": "tabletop", "name": "MediumTable", "x": -12.0, "z": 52.0, "speed": 18.0, "lip": 9.0, "width": 9.0, "pop": 0.72},
		{"kind": "moguls", "name": "MidMoguls", "x": -1.0, "z": 67.0, "rows": 5, "spacing": 4.4, "height": 0.48, "width": 4.5},
		{"kind": "butter", "name": "MidButterPad", "x": 0.0, "z": 43.0, "length": 13.0, "width": 9.0, "height": 0.12},
		{"kind": "rail", "name": "KinkRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.7, "approach": 40.0, "drift_bias": 0.28, "points": [Vector3(10.0, 68.0, 0.16), Vector3(10.0, 58.0, 0.16), Vector3(15.0, 46.0, 0.16)]},
		{"kind": "rail", "name": "DFDBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.15, "friction": 1.05, "approach": 50.0, "drift_bias": -0.18, "points": [Vector3(10.0, 40.0, 0.22), Vector3(10.0, 28.0, -0.68), Vector3(10.0, 16.0, 0.22)]},
		{"kind": "wallride", "name": "MidWallride", "x": 24.0, "z": 45.0, "length": 13.0, "height": 4.0, "yaw": 8.0, "color": Color("#ef8354")},

		# Transfer zone.
		{"kind": "hip", "name": "HipTransfer", "x": -12.0, "z": 12.0, "speed": 16.0, "lip": 8.0, "yaw": 28.0, "pop": 0.72},
		{"kind": "side_hit", "name": "CenterSpine", "x": 0.0, "z": 30.0, "length": 12.0, "height": 1.8, "width": 8.0, "yaw": -12.0},
		{"kind": "roller", "name": "MidRoller", "x": 0.0, "z": -8.0, "length": 9.0, "height": 0.7, "width": 12.0},
		{"kind": "rail", "name": "LongTube", "rail_type": GrindRail3D.RailType.PIPE, "radius": 0.76, "friction": 0.45, "approach": 40.0, "drift_bias": 0.20, "points": [Vector3(18.0, 8.0, 0.14), Vector3(18.0, -18.0, 0.14)]},
		{"kind": "rail", "name": "TransferBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.1, "friction": 0.95, "approach": 48.0, "drift_bias": -0.24, "points": [Vector3(14.0, 4.0, 0.22), Vector3(2.0, -22.0, 0.22)]},
		{"kind": "bonk", "name": "TransferBonk", "x": 24.0, "z": -8.0, "height": 1.8, "radius": 0.5, "color": Color("#55d6be")},

		# Lower park.
		{"kind": "tabletop", "name": "LargeTable", "x": -12.0, "z": -32.0, "speed": 22.0, "lip": 11.0, "width": 10.0, "pop": 0.72},
		{"kind": "side_hit", "name": "LowerRightSideHit", "x": 25.0, "z": -32.0, "length": 10.0, "height": 1.45, "width": 7.0, "yaw": 22.0},
		{"kind": "butter", "name": "LowerButterPad", "x": -1.0, "z": -44.0, "length": 16.0, "width": 10.0, "height": 0.14},
		{"kind": "rail", "name": "SRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.8, "friction": 0.7, "approach": 38.0, "drift_bias": 0.30, "points": [Vector3(16.0, -24.0, 0.16), Vector3(9.0, -36.0, 0.16), Vector3(16.0, -48.0, 0.16)]},
		{"kind": "rail", "name": "Rainbow", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.82, "friction": 0.6, "approach": 40.0, "drift_bias": -0.28, "points": [Vector3(16.0, -50.0, 0.16), Vector3(16.0, -58.0, 3.2), Vector3(16.0, -70.0, 0.16)]},
		{"kind": "wallride", "name": "LowerWallride", "x": 27.0, "z": -61.0, "length": 15.0, "height": 4.5, "yaw": -8.0, "color": Color("#55d6be")},

		# Finale and runout.
		{"kind": "tabletop", "name": "StepDownTable", "x": -12.0, "z": -88.0, "speed": 18.0, "lip": 8.0, "width": 8.5, "drop": 3.0, "pop": 0.72},
		{"kind": "cannon", "name": "FinalCannon", "x": -2.0, "z": -91.0, "length": 11.0, "width": 5.5, "height": 1.7},
		{"kind": "rail", "name": "FinalBox", "rail_type": GrindRail3D.RailType.BOX, "radius": 1.05, "friction": 1.1, "approach": 46.0, "drift_bias": 0.18, "points": [Vector3(8.0, -96.0, 0.22), Vector3(8.0, -118.0, 0.22)]},
		{"kind": "rail", "name": "FinalDFDRail", "rail_type": GrindRail3D.RailType.RAIL, "radius": 0.8, "friction": 0.68, "approach": 38.0, "drift_bias": -0.30, "points": [Vector3(18.0, -92.0, 0.18), Vector3(18.0, -102.0, 0.75), Vector3(18.0, -114.0, 0.18)]},
		{"kind": "berm", "name": "FinalCatchBerm", "x": 0.0, "z": -128.0, "length": 18.0, "width": 14.0, "bank": 9.0, "yaw": 0.0},
		{"kind": "gate", "name": "FinishGate", "x": 0.0, "z": -151.0, "width": 50.0, "color": Color("#ff9f1c")},
	]
