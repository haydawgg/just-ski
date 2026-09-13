extends "res://world/resort_base.gd"

const ProductionCameraController := preload("res://player/production_camera_controller.gd")

## Production specialization of the resort player/camera seam. The environment,
## course, probe, settings and presentation implementation remains in
## resort_base.gd; only the camera class differs so integrated gameplay uses the
## trajectory-curvature turn lead while all existing resort contracts stay
## unchanged.
func _build_player() -> void:
	player = SkierController.new()
	player.name = "Skier"
	player.profile = physics_profile
	player.position = ParkLayout.spawn_position(course_profile.spawn_world_z() if course_profile != null else ParkLayout.DEFAULT_SPAWN_WORLD_Z)
	player.basis = ParkLayout.downhill_basis()
	add_child(player)
	for node: Node in player.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	SessionManager.set_default_spawn(player.global_transform)
	course_recovery = CourseRecoveryModule.new()
	course_recovery.name = "CourseRecovery"
	add_child(course_recovery)
	course_recovery.set_target(player)
	course_recovery.course_profile = course_profile
	if course_profile != null:
		course_recovery.maximum_z = course_profile.spawn_world_z() + 10.0
		course_recovery.minimum_z = course_profile.finish_trigger_world_z() - 20.0

	camera_rig = ProductionCameraController.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.set_target(player)
	player.respawn_applied.connect(_on_player_respawn_applied)

	var ui := GameUI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.call_deferred("bind_player", player)
	ui.call_deferred("bind_camera", camera_rig)
	content_tracker = ParkContentTracker.new()
	content_tracker.name = "ParkContentTracker"
	add_child(content_tracker)
	content_tracker.configure(course_profile, player)
	ui.call_deferred("bind_content_tracker", content_tracker)
	ui.recovery_fade_out_duration = course_recovery.fade_out_duration
	ui.recovery_fade_in_duration = course_recovery.fade_in_duration
	course_recovery.recovery_started.connect(ui.notify_course_recovery)
	course_recovery.recovery_respawned.connect(ui.complete_course_recovery)
	course_recovery.recovery_completed.connect(ui.finish_course_recovery)
	course_recovery.recovery_cancelled.connect(ui.cancel_course_recovery)
	_build_finish_trigger()
