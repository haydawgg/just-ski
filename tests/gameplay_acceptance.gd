extends Node

const ParkLayout := preload("res://world/park_features/park_layout.gd")

# A charged keyboard pop is a short hop, not a launch. Keep this behavioral
# envelope tied to the route fixture so a physics-profile change cannot make
# ordinary jumps silently regain the old, floaty feel.
const REFERENCE_POP_MAX_PEAK_HEIGHT := 1.10
const REFERENCE_POP_MAX_AIR_SECONDS := 0.90
const REFERENCE_POP_MAX_TAKEOFF_UPWARD_SPEED := 3.80

@onready var resort: Node = $Resort
var skier: SkierController
var frame := 0
var failures: Array[String] = []
var carve_start_x := 0.0
var carve_start_yaw := 0.0
var carve_start_speed := 0.0
var carve_min_speed := INF
var carve_start_pos := Vector3.ZERO
var carve_start_right := Vector3.ZERO
var speed_before_brake := 0.0
var air_seen := false
var marker_position := Vector3.ZERO
var pop_started := false
var pop_completed := false
var pop_takeoff_position := Vector3.ZERO
var pop_takeoff_upward_speed := 0.0
var pop_peak_height := 0.0
var pop_air_frames := 0

func _ready() -> void:
	skier = resort.get_node("Skier") as SkierController
	_test_landing_solver()
	_test_low_speed_steering_tuning()
	_test_jump_table()
	_test_rail_filtering.call_deferred()

func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 180:
		carve_start_x = skier.global_position.x
		carve_start_pos = skier.global_position
		carve_start_yaw = _heading_yaw()
		carve_start_speed = skier.velocity.length()
		carve_min_speed = carve_start_speed
		var start_forward := (-skier.global_basis.z).slide(Vector3.UP)
		carve_start_right = start_forward.cross(Vector3.UP).normalized() if start_forward.length_squared() > 0.01 else Vector3.RIGHT
		if skier.state != SkierController.State.GROUND:
			failures.append("Skier was not grounded when carve input began")
		Input.action_press("steer_left", 1.0)
	elif frame > 180 and frame < 330:
		carve_min_speed = minf(carve_min_speed, skier.velocity.length())
	elif frame == 330:
		Input.action_release("steer_left")
		var lateral_travel := absf((skier.global_position - carve_start_pos).dot(carve_start_right))
		var heading_delta := absf(angle_difference(carve_start_yaw, _heading_yaw()))
		print("CARVE_TELEMETRY lateral=", lateral_travel, " heading_deg=", rad_to_deg(heading_delta), " speed=", skier.velocity.length(), " start_speed=", carve_start_speed, " state=", SkierController.State.keys()[skier.state], " dx=", skier.global_position.x - carve_start_x)
		if skier.state != SkierController.State.GROUND:
			failures.append("Skier left the snow during the carve")
		if lateral_travel < 1.0:
			failures.append("Carve input did not produce meaningful lateral travel")
		if lateral_travel < 1.0 or lateral_travel > 4.0:
			failures.append("Reference carve lateral travel %.2f m left the approved 1-4 m realistic band" % lateral_travel)
		# This is a short, low-speed feel check. The isolated physics benchmark
		# owns the sustained >120-degree carve test at representative speed.
		if heading_delta < deg_to_rad(25.0) or heading_delta > deg_to_rad(55.0):
			failures.append("Reference carve heading %.1f degrees left the approved 25-55 degree realistic band" % rad_to_deg(heading_delta))
		if carve_start_speed > 6.0 and carve_min_speed < carve_start_speed * 0.55:
			failures.append("Extended carve hit a collision-scale speed collapse (minimum ratio %.2f)" % (carve_min_speed / carve_start_speed))
		if carve_start_speed > 6.0 and skier.velocity.length() < carve_start_speed * 0.35:
			failures.append("Carve destroyed too much speed instead of redirecting it")
		var carve_speed_ratio := skier.velocity.length() / maxf(carve_start_speed, 0.01)
		if carve_speed_ratio < 1.35 or carve_speed_ratio > 2.25:
			failures.append("Reference carve speed ratio %.2f left the approved 1.35-2.25 gravity-driven band" % carve_speed_ratio)
		Input.action_press("jump", 1.0)
	elif frame == 350:
		Input.action_release("jump")
	elif frame > 350 and frame < 480:
		if skier.state == SkierController.State.AIR:
			air_seen = true
			if not pop_started:
				pop_started = true
				pop_takeoff_position = skier.global_position
				pop_takeoff_upward_speed = skier.air_takeoff_upward_speed
			pop_air_frames += 1
			pop_peak_height = maxf(pop_peak_height, (skier.global_position - pop_takeoff_position).dot(ParkLayout.snow_normal()))
		elif pop_started:
			pop_completed = true
	elif frame == 480:
		if not air_seen:
			failures.append("Charged pop never entered Air state")
		var pop_air_seconds := float(pop_air_frames) / float(Engine.physics_ticks_per_second)
		print("POP_TELEMETRY peak_m=", pop_peak_height, " air_seconds=", pop_air_seconds, " takeoff_upward_mps=", pop_takeoff_upward_speed, " completed=", pop_completed)
		if pop_peak_height < 0.65 or pop_peak_height > REFERENCE_POP_MAX_PEAK_HEIGHT:
			failures.append("Reference pop peak %.2f m left the approved 0.65-%.2f m short-hop band" % [pop_peak_height, REFERENCE_POP_MAX_PEAK_HEIGHT])
		if pop_air_seconds < 0.55 or pop_air_seconds > REFERENCE_POP_MAX_AIR_SECONDS:
			failures.append("Reference pop airtime %.2f s left the approved 0.55-%.2f s short-hop band" % [pop_air_seconds, REFERENCE_POP_MAX_AIR_SECONDS])
		if pop_takeoff_upward_speed > REFERENCE_POP_MAX_TAKEOFF_UPWARD_SPEED:
			failures.append("Reference pop takeoff %.2f m/s exceeded the %.2f m/s short-hop cap" % [pop_takeoff_upward_speed, REFERENCE_POP_MAX_TAKEOFF_UPWARD_SPEED])
		marker_position = skier.global_position + Vector3.UP * 0.35
		var marker_transform := skier.global_transform
		marker_transform.origin = marker_position
		SessionManager.set_marker(marker_transform)
		skier.global_position += Vector3(9.0, 4.0, 0.0)
		SessionManager.request_respawn()
	elif frame == 500:
		if skier.global_position.distance_to(marker_position + Vector3.UP * 0.35) > 1.0:
			failures.append("Session marker respawn did not restore the saved position")
	elif frame == 620:
		speed_before_brake = skier.velocity.length()
		Input.action_press("brake", 1.0)
	elif frame == 740:
		Input.action_release("brake")
		if speed_before_brake > 4.0 and skier.velocity.length() >= speed_before_brake:
			failures.append("Brake did not reduce speed")
	elif frame == 760:
		_finish()

func _test_jump_table() -> void:
	var profile: SkiPhysicsProfile = resort.physics_profile
	var sizing := ParkLayout.jump_table(profile, 18.0, 9.0, 0.0, profile.minimum_pop_strength)
	var table_length := float(sizing.table_length)
	if table_length < 8.0 or table_length > 20.0:
		failures.append("Ballistic table length %.2f was outside the 8-20 m design band" % table_length)
	if float(sizing.lip_length) < 7.0 or float(sizing.landing_length) < 8.0:
		failures.append("Jump table lip/landing lengths were not authored for a rideable tabletop")

func _test_landing_solver() -> void:
	var profile := SkiPhysicsProfile.new()
	var clean := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0, -3, -10), Vector3.ZERO, profile)
	var charged_pop := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0, -8.5, -12), Vector3.ZERO, profile)
	var heavy_air := LandingSolver.evaluate(Vector3.UP, Vector3.FORWARD, Vector3.UP, Vector3(0, -10.0, -12), Vector3.ZERO, profile)
	var failed := LandingSolver.evaluate(Vector3.DOWN, Vector3.FORWARD, Vector3.UP, Vector3(0, -22, -10), Vector3(8, 5, 2), profile)
	if int(clean.outcome) != LandingSolver.Outcome.CLEAN:
		failures.append("Nominal aligned landing was not classified clean")
	if int(charged_pop.outcome) != LandingSolver.Outcome.CLEAN:
		failures.append("Well-aligned charged-pop impact was not classified clean")
	if int(heavy_air.outcome) != LandingSolver.Outcome.SKETCHY:
		failures.append("Impact beyond the widened clean window was not classified sketchy")
	if int(failed.outcome) != LandingSolver.Outcome.BAIL:
		failures.append("Upside-down high-impact landing was not classified bail")

func _test_low_speed_steering_tuning() -> void:
	var profile := SkiPhysicsProfile.new()
	var speed := 3.0
	var speed_ratio := speed / profile.steering_speed_reference
	var base_rate := lerpf(profile.low_speed_steering, profile.high_speed_steering, speed_ratio)
	var speed_gate := clampf(speed / profile.full_steer_speed, profile.minimum_steer_speed_gate, 1.0)
	var unbraked_rate := base_rate * speed_gate + speed * profile.sidecut
	var brake_rate := base_rate * profile.brake_steer_multiplier + speed * profile.sidecut
	if rad_to_deg(unbraked_rate) > 30.0:
		failures.append("Low-speed full steer still permits a %.1f degree/s pirouette" % rad_to_deg(unbraked_rate))
	if brake_rate < unbraked_rate * 2.0:
		failures.append("Brake input no longer preserves a deliberate low-speed hockey-stop pivot")

func _test_rail_filtering() -> void:
	var rail := resort.get_node("DownRail") as GrindRail3D
	var offset := rail.path_length * 0.5
	var position := rail.sample_world(offset) + Vector3.UP * 0.25
	var tangent := rail.tangent_at(offset)
	var valid := rail.capture_candidate(position, tangent * 10.0, 1.2, 3.0)
	var invalid := rail.capture_candidate(position + Vector3.RIGHT * 4.0, tangent * 10.0, 1.2, 3.0)
	if not bool(valid.get("valid", false)):
		failures.append("Plausible rail approach was rejected")
	if bool(invalid.get("valid", false)):
		failures.append("Far rail approach was incorrectly captured")

func _heading_yaw() -> float:
	var forward := -skier.global_basis.z
	return atan2(forward.x, forward.z)

func _finish() -> void:
	Input.action_release("steer_left")
	Input.action_release("jump")
	Input.action_release("brake")
	print("ACCEPTANCE_TELEMETRY position=", skier.global_position, " speed_mps=", skier.velocity.length(), " state=", SkierController.State.keys()[skier.state])
	AudioManager.shutdown_audio()
	if failures.is_empty():
		print("ACCEPTANCE_PASS: carve, pop, respawn, brake, landing, and rail entry checks passed")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("ACCEPTANCE_FAIL: " + failure)
		get_tree().quit(1)
