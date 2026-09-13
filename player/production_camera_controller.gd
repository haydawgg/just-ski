class_name ProductionSkiCameraController
extends "res://player/camera_controller.gd"

## Production camera specialization for clean-carve composition.
##
## The base rig historically used heading/travel divergence as its signed turn
## lead input. That is appropriate for skids and hockey stops, but a clean carve
## can keep the ski heading nearly aligned with travel while still following a
## strong curved trajectory. During ordinary grounded carving, feed a bounded
## camera-only signal derived from the real edge/steering state into the base
## composition pass, then restore the skier's true heading/travel telemetry
## immediately afterward. Physics, HUD, VFX, and scoring therefore keep the
## original semantic value.

@export_range(2.0, 45.0, 1.0) var carve_signal_max_degrees := 28.0
@export_range(0.0, 1.0, 0.05) var carve_signal_edge_threshold := 0.08

func _physics_process(delta: float) -> void:
	var skier := target as SkierController
	var original_heading_travel := 0.0
	var injected := false
	if skier != null:
		original_heading_travel = skier.heading_travel_angle_degrees
		if skier.state == SkierController.State.GROUND and not skier.braking and absf(skier.edge_amount) >= carve_signal_edge_threshold:
			var camera_signal := skier.edge_amount * carve_signal_max_degrees
			if absf(camera_signal) > absf(original_heading_travel):
				skier.heading_travel_angle_degrees = camera_signal
				injected = true
	super(delta)
	if injected and skier != null:
		skier.heading_travel_angle_degrees = original_heading_travel
