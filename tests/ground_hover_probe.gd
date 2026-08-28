extends Node

# Regression probe for ground contact: the skier must stay seated on the snow
# surface while grounded (no floating), never wedge permanently against
# geometry, and survive a straight run over rollers, moguls, berms, butter
# pads, rails, and the finish runout.
const SEAT_DISTANCE := 0.54
const GAP_LIMIT := 0.35
const GAP_SUSTAINED_FRAMES := 30

var frame_count := 0
var gap_frames := 0
var worst_gap := 0.0
var worst_gap_info := ""
var stuck_frames := 0
var stuck_reported := false
@onready var resort: Node = $Resort

func _ready() -> void:
	# The run crosses the finish trigger, which pauses the tree through the
	# results UI. Keep ticking so the probe can report success.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		print("HOVER_RESULT finish_reached=true worst_gap=%.2f (%s) stuck=%s" % [worst_gap, worst_gap_info, stuck_reported])
		_finish(stuck_reported)
		return
	frame_count += 1
	var skier := resort.get_node_or_null("Skier") as SkierController
	if skier == null:
		if frame_count > 120:
			push_error("HOVER_FAIL: Skier was not created")
			get_tree().quit(1)
		return
	var hover := _hover_distance(skier)
	if frame_count % 60 == 0:
		var data := skier.telemetry()
		print("HOVER_SAMPLE frame=%d pos=%s state=%s grounded=%s hover=%.2f speed=%.1f surf=%s" % [
			frame_count, skier.global_position, data.state, data.grounded, hover, skier.velocity.length(), data.surface])
	# Seat-gap duration: brief arcs over features are fine; a persistent gap
	# while "grounded" is the floating regression.
	var seat_gap := skier.contact.average_distance - SEAT_DISTANCE
	if frame_count > 150 and skier.state == SkierController.State.GROUND and skier.contact.grounded and seat_gap > GAP_LIMIT:
		gap_frames += 1
		if seat_gap > worst_gap:
			worst_gap = seat_gap
			worst_gap_info = "frame=%d z=%.1f" % [frame_count, skier.global_position.z]
	else:
		gap_frames = 0
	# Falling behind the seat is fine (spawn drop); a long AIR glide that never
	# reseats is not.
	if frame_count > 150 and skier.state == SkierController.State.AIR and skier.air_time > 2.5 and skier.velocity.length() > 1.0 and _near_surface(skier):
		push_error("HOVER_FAIL: airborne glide near the surface lasted %.1f s at %s" % [skier.air_time, skier.global_position])
		_finish(true)
		return
	if skier.velocity.length() < 0.1:
		stuck_frames += 1
		if stuck_frames >= 45 and not stuck_reported:
			stuck_reported = true
			_report_stuck(skier)
	else:
		stuck_frames = 0
	if frame_count >= 2400:
		print("HOVER_RESULT worst_gap=%.2f (%s) sustained_gap_frames=%d stuck=%s" % [worst_gap, worst_gap_info, gap_frames, stuck_reported])
		_finish(worst_gap > GAP_LIMIT + 0.3 or gap_frames >= GAP_SUSTAINED_FRAMES or stuck_reported)

func _near_surface(skier: SkierController) -> bool:
	return skier.contact.average_distance < 1.4 and skier.contact.confidence >= 0.5

func _finish(failed: bool) -> void:
	if failed:
		push_error("HOVER_FAIL: see details above")
		AudioManager.shutdown_audio()
		get_tree().quit(2)
		return
	print("HOVER_PASS: skier stayed seated on the surface for the full run")
	AudioManager.shutdown_audio()
	get_tree().quit(0)

func _hover_distance(skier: SkierController) -> float:
	var space := skier.get_world_3d().direct_space_state
	var origin := skier.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 6.0, 1)
	query.exclude = [skier.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return skier.global_position.y - (hit.position as Vector3).y

func _report_stuck(skier: SkierController) -> void:
	print("STUCK_REPORT pos=%s vel=%s state=%s slide_count=%d" % [skier.global_position, skier.velocity, skier.state, skier.get_slide_collision_count()])
	for i in range(skier.get_slide_collision_count()):
		var collision := skier.get_slide_collision(i)
		print("  SLIDE %d collider=%s normal=%s" % [i, collision.get_collider().name if collision.get_collider() else "<null>", collision.get_normal()])
