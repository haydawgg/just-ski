extends Node

var frame_count := 0
@onready var resort: Node3D = $Resort

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count < 360:
		return
	var failures: Array[String] = []
	var skier := resort.get_node_or_null("Skier") as SkierController
	if skier == null:
		failures.append("Resort did not create the skier")
	else:
		var vfx := skier.get_node_or_null("SkiSnowVFX") as SkiSnowVFX
		if vfx == null:
			failures.append("Skier is missing the presentation-only snow VFX component")
		else:
			var snapshot := vfx.debug_snapshot()
			if not bool(snapshot.uses_existing_contact):
				failures.append("Snow VFX is not bound to the existing skier contact data")
			if int(snapshot.left_track_samples) < 4 or int(snapshot.right_track_samples) < 4:
				failures.append("Normal resort travel did not produce both bounded ski tracks")
			if int(snapshot.left_track_samples) > int(snapshot.track_cap) or int(snapshot.right_track_samples) > int(snapshot.track_cap):
				failures.append("Persistent track history exceeded its hard cap")
			if int(snapshot.continuous_particle_cap) > 200:
				failures.append("Continuous snow particle budget exceeded the acceptance ceiling")
			if not vfx.find_children("*", "RayCast3D", true, false).is_empty():
				failures.append("Snow VFX created a second terrain-contact system")
			var track_mesh := vfx.get_node_or_null("PersistentSkiTracks") as MeshInstance3D
			if track_mesh == null or track_mesh.mesh == null or track_mesh.mesh.get_surface_count() == 0:
				failures.append("Track ribbon mesh was not generated")
			var result := {
				"score": 0.76,
				"impact_severity": 0.72,
				"lateral_velocity": 2.0,
			}
			skier.landed.emit(result)
			if float(vfx.debug_snapshot().landing_severity) < 0.7:
				failures.append("Landing severity did not reach the one-shot landing burst")
			if not vfx.landing_spray.emitting:
				failures.append("Hard landing did not restart the one-shot landing emitter")
	if failures.is_empty():
		print("ENVIRONMENT_VISUAL_PASS: existing contact drives capped twin tracks, carve/skid/speed spray, and landing bursts")
		AudioManager.shutdown_audio()
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ENVIRONMENT_VISUAL_FAIL: " + failure)
		AudioManager.shutdown_audio()
		get_tree().quit(1)
